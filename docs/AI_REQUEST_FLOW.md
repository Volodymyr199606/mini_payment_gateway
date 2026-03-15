# AI Request Flow

This doc describes the end-to-end path of an AI chat request as implemented in the dashboard and API controllers. Flow is the same in spirit for API; entrypoint differs.

## 1. Entry and context

- **Input**: User message, `current_merchant` (dashboard) or API auth → merchant.
- **Session**: Chat uses `AiChatSession` / `AiChatMessage`; message is stored as user turn.
- **Context**: `CachedConversationContextBuilder` loads summary + recent messages (and related context) for the session. Used for intent resolution and, later, memory.

## 2. Intent and follow-up resolution

- **IntentResolver** is called with: `message`, `recent_messages`, `merchant_id`.
- It returns:
  - **intent**: `nil` or `{ tool_name:, args: }` (from IntentDetector when a single tool is clearly indicated).
  - **followup**: e.g. `followup_detected`, `followup_type`, `inherited_entities`, `inherited_time_range`, `response_style_adjustments`.
- Follow-up resolution runs **before** routing and planning so inherited context (entity, time range) is available and policy can validate it.

## 3. Routing and execution plan

- **Router** (keyword-based) returns an agent key (e.g. `:support_faq`, `:reporting_calculation`). Optional `agent` param can override (e.g. playground).
- **RequestPlanner.plan** is called with `message`, `intent_resolution`, `agent_key`.
  - **If intent present**: Returns plan with `execution_mode: :deterministic_only`, `skip_retrieval: true`, `skip_memory: true`, `skip_orchestration: false`. No RAG or agent call; orchestration will run.
  - **If no intent**: Plans agent path: `execution_mode` (e.g. `:agent_full`, `:concise_rewrite_only`), `skip_retrieval` / `skip_memory` from agent definition (e.g. `supports_retrieval?`, `supports_memory?`), `retrieval_budget_reduced` for rewrite follow-ups.
- **ExecutionPlan** is logged (when safe) and passed through; it is written to audit at the end.

## 4. Deterministic tool path (orchestration)

- **ConstrainedRunner** is always called with `message`, `merchant_id`, `request_id`, `resolved_intent` (from IntentResolver).
- If **no intent** or **merchant missing**: Returns `RunResult.no_orchestration`.
- **Policy**: `Policy::Engine#allow_orchestration?` is checked (merchant present, intent present); if denied, no orchestration.
- **Step 1**: `Tools::Executor.call(tool_name, args, context)`. Executor uses `Registry.resolve`, policy `allow_tool?`, optional cache (CachePolicy + tool definition `cacheable?`). Tool returns `{ success, data }` or error. Explanation is rendered via `Explanations::Renderer` or `Tools::Formatter`.
- **Step 2** (optional): Only if FOLLOW_UP_RULES allow (e.g. `get_transaction` → `get_payment_intent`) and step 1 succeeded with linkable data. Same Executor + policy. Reply is built from step outputs.
- If **orchestration_used?**: Controller composes response via `ResponseComposer`, writes audit (tool path, orchestration metadata), returns. **No retrieval, no agent, no LLM.**

```
  [intent present] → RequestPlanner(deterministic_only)
       → ConstrainedRunner → Policy.allow_orchestration?
       → Executor (step 1) [→ optional step 2]
       → ResponseComposer(tool/orchestration) → Audit → response
```

## 5. Agent + RAG path (no orchestration)

When ConstrainedRunner did **not** run (no intent or policy denied):

- **Memory** (unless plan says skip): `Conversation::MemoryBudgeter` builds `memory_text` from summary + recent messages (and related context). Used as context for the agent.
- **Retrieval**: `CachedRetrievalService.call(message, agent_key:, **retrieval_opts)`. Uses agent’s RAG policy (allowed/preferred docs). Result: `context_text`, `citations`. Skipped if plan has `skip_retrieval` (e.g. agent with `supports_retrieval: false`).
- **Agent**: `AgentRegistry.fetch(agent_key)` → agent class. Agent is built with message, context_text, citations, conversation_history, memory_text. **Agent.call** runs LLM (or low-context fallback) and returns reply + citations.
- **Composition**: `ResponseComposer` builds final reply, citations, composition metadata (used_tool_data, used_doc_context, used_memory_context, etc.).
- **Audit**: Audit record includes agent_key, retriever_key, composition, execution_plan_metadata, memory_used, citations_count, etc.

```
  [no intent or orchestration not used]
       → ExecutionPlan (agent_full / concise_rewrite / etc.)
       → MemoryBudgeter (unless skip_memory)
       → CachedRetrievalService (unless skip_retrieval)
       → Agent.call → ResponseComposer → Audit → response
```

## 6. Response composition

- **ResponseComposer** receives: reply_text, citations, agent_key, model_used, fallback_used, data, memory_used, optional tool/explanation metadata.
- Produces a consistent payload: `reply`, `agent_key`, `citations`, `model_used`, `fallback_used`, `data`, and **composition** (mode, used_tool_data, used_doc_context, citations_count, etc.). Composition is versioned (see AI_INTERFACE_CONTRACTS.md).

## 7. Audit and observability

- Every successful or degraded response triggers **AuditTrail::Writer** (or equivalent) with a record built by **RecordBuilder**: request_id, endpoint, merchant_id, agent_key, composition, tool_used, tool_names, latency_ms, execution_plan_metadata, followup_metadata, policy_metadata, etc. **No prompts or secrets.**
- **EventLogger** logs tool calls, cache events, and (when AI_DEBUG) builds debug payload. Debug exposure is gated by policy `allow_debug_exposure?` (no prompt/api_key in payload).

## 8. Resilience and degraded paths

- On **exception** in the controller, **Resilience::Coordinator** is used: infer failure stage (generation, retrieval, tool, orchestration, memory, streaming, etc.), choose fallback mode, return a **safe message** and optional prior tool data.
- Response is still returned with 200; payload indicates degraded outcome. Audit can record failure and resilience metadata.

## Flow summary (single diagram)

```
  Message + Session
        │
        ▼
  CachedConversationContextBuilder ──► IntentResolver ──► intent + followup
        │                                                      │
        ▼                                                      ▼
  Router (agent_key) ──► RequestPlanner.plan(intent_resolution, agent_key)
        │                                                      │
        │         ┌────────────────────────────────────────────┘
        │         │
        ▼         ▼
  ExecutionPlan (deterministic_only | agent_full | …)
        │
        ├── [intent present] ──► ConstrainedRunner
        │                              │
        │                              ├── allow_orchestration? ──► no ──► skip
        │                              └── yes ──► Executor(step1) [→ step2]
        │                                              │
        │                                              ▼
        │                              ResponseComposer(tool) ──► Audit ──► response
        │
        └── [no orchestration] ──► MemoryBudgeter (optional)
                                        │
                                        ▼
                                  CachedRetrievalService (optional)
                                        │
                                        ▼
                                  Agent.call ──► ResponseComposer(agent) ──► Audit ──► response
```

## Streaming

When streaming is enabled and the path is agent (not tool): the controller uses `perform_streaming_chat`, which streams the agent reply. Composition and audit are still written after the stream completes. Tool/orchestration path does not stream.
