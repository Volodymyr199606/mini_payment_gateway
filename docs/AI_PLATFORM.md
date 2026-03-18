# AI Internal Platform — Overview

The AI subsystem is an **internal platform** inside the Rails payment gateway: multi-tenant, merchant-scoped, read-only. This doc is the entry point for architecture, operations, and safe extension.

## Scope

- **In scope**: Multi-agent routing, RAG (retrieval over docs), deterministic tools, intent/follow-up resolution, request planning, constrained orchestration, conversation memory, guardrails, audit trail, observability, caching, resilience, streaming, dev playground, analytics, health checks, versioned RAG corpus, explanation templates, audit drill-down, replay debugging, and plugin-style agent/tool registries.
- **Out of scope**: Autonomous agents, write operations, external plugin loading, or exposing raw prompts/secrets to merchants.

## Entrypoints

| Entrypoint | Controller | Purpose |
|------------|------------|---------|
| Dashboard chat | `Dashboard::AiController#chat` | Merchant-facing AI chat (rate-limited). |
| API chat | `Api::V1::Ai::ChatController` | API AI chat for programmatic access. |
| Dev playground | `Dev::AiPlaygroundController#show` / `#run` | Internal scenario runs; dev/test only. |
| Dev analytics | `Dev::AiAnalyticsController#index` | Aggregated metrics from `ai_request_audits`; dev only. |
| Dev health | `Dev::AiHealthController#show` | SLO/health report and corpus state; dev only. |
| Dev audits | `Dev::AiAuditsController#index` / `#show` / `#replay` | Audit list, detail, and replay; dev only. |

All AI requests are **merchant-scoped**. Policy enforces tenant isolation before any tool or orchestration runs.

## Internal doc index

| Doc | Purpose |
|-----|---------|
| **AI_PLATFORM.md** (this file) | Overview, entrypoints, doc index, safe vs risky changes. |
| [AI_REQUEST_FLOW.md](AI_REQUEST_FLOW.md) | End-to-end request flow: intent → plan → orchestration vs agent/RAG → composition → audit. |
| [AI_EXTENSION_GUIDE.md](AI_EXTENSION_GUIDE.md) | How to add agents and tools; registry metadata; validations. |
| [AI_OPERATIONS.md](AI_OPERATIONS.md) | Analytics, health, audit drill-down, replay, cache/corpus, resilience, debugging regressions. |
| [AI_SAFETY_AND_POLICY.md](AI_SAFETY_AND_POLICY.md) | Merchant scoping, policy engine, tool/orchestration limits, debug exposure, trust boundaries. |
| [AI_DEBUGGING_AND_REPLAY.md](AI_DEBUGGING_AND_REPLAY.md) | Inspecting audits, replay workflow, what replay can/cannot do, useful metadata. |
| [AI_DEPLOYMENT_AND_RELEASE_SAFETY.md](AI_DEPLOYMENT_AND_RELEASE_SAFETY.md) | Feature flags, startup validation, production safety, rollout controls, config visibility. |
| [AI_INTERFACE_CONTRACTS.md](AI_INTERFACE_CONTRACTS.md) | Contract versions and field names for payloads (ParsedIntent, ExecutionPlan, ToolResult, etc.). |
| [AI_RAG_AUDIT.md](AI_RAG_AUDIT.md) | RAG component map and per-component notes (reference). |

## High-level architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Entrypoints: Dashboard::AiController, Api::V1::Ai::ChatController, Dev  │
└─────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  Context + Intent: CachedConversationContextBuilder, IntentResolver      │
│  Planning: Router → RequestPlanner → ExecutionPlan                        │
└─────────────────────────────────────────────────────────────────────────┘
                                      │
              ┌───────────────────────┴───────────────────────┐
              ▼                                               ▼
┌─────────────────────────────┐               ┌─────────────────────────────┐
│  Deterministic path         │               │  Agent/RAG path             │
│  ConstrainedRunner          │               │  CachedRetrievalService     │
│  (intent present, policy OK)│               │  MemoryBudgeter → Agent     │
│  Tools::Executor, Formatter  │               │  ResponseComposer           │
└─────────────────────────────┘               └─────────────────────────────┘
              │                                               │
              └───────────────────────┬───────────────────────┘
                                      ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  Policy (Engine + Authorization), AuditTrail::Writer, Observability     │
│  Resilience (Coordinator) on failure                                    │
└─────────────────────────────────────────────────────────────────────────┘
```

- **Single path per request**: Either orchestration (deterministic tools) **or** agent + RAG (+ optional memory). RequestPlanner and intent resolution decide which path.
- **Registries**: `Ai::AgentRegistry` and `Ai::Tools::Registry` (with definitions) are the single source of truth for agents and tools; used by Router, RequestPlanner, Executor, CachePolicy.

## Safe to change vs risky to change

Use this when planning changes or reviewing PRs.

### Relatively safe to change

- **Explanation templates** (`Ai::Explanations::*`): Text and structure of deterministic explanations; no change to data access or policy.
- **Registry metadata**: Adding or editing `AgentDefinition` / `ToolDefinition` (descriptions, `supports_retrieval`, `cacheable`, etc.) as long as validations still pass and behavior stays consistent (e.g. only cacheable tools cached).
- **Analytics presentation**: Views and queries for the dev analytics dashboard; no impact on live request path.
- **Internal dev tools**: Playground, audit list/detail UI, replay UI (as long as they don’t change how audits are written or how replay builds input).
- **RAG doc content**: Adding/editing markdown in `docs/` used by RAG; corpus versioning and retrieval logic stay as-is.
- **Safe fallback messages**: Text in `Ai::Resilience::Coordinator::SAFE_MESSAGES`; user-facing only.

### Risky — need care and tests

- **Request flow ordering**: Order of steps in `AiController#chat` (intent → plan → orchestration vs retrieval/memory/agent). Changing order can break policy, caching, or composition.
- **Policy engine rules**: `Ai::Policy::Engine` and `Ai::Policy::Authorization` (e.g. `allow_tool?`, `allow_orchestration?`, `allow_record?`, `allow_followup_inheritance?`). Changes affect security and tenant isolation.
- **Orchestration limits**: `ConstrainedRunner` (MAX_STEPS, FOLLOW_UP_RULES). Relaxing can increase cost and complexity; tightening can change behavior for existing flows.
- **Retrieval cache keys**: `CacheKeys.tool`, retrieval keys, memory keys. Key shape changes can cause wrong cache hits/misses or cross-tenant leakage if merchant_id is dropped.
- **Audit/debug contracts**: Fields and schema written by `AuditTrail::RecordBuilder` or `EventLogger.build_debug_payload`; consumed by analytics, replay, and drill-down. Changing fields or semantics can break downstream.
- **Source-of-truth composition rules**: How `ResponseComposer` combines tool vs docs vs memory; what is considered “deterministic” vs “agent”. Changes affect correctness and guardrails.

### Do not do

- **No-write AI**: Tools must remain read-only; no creating/updating/deleting records from the AI path.
- **No prompt/secret exposure**: Debug payload must not include prompts or API keys; policy and `allow_debug_exposure?` enforce this.
- **No dynamic plugin loading**: Agent and tool registration stays explicit in code (registries); no loading from arbitrary files or user input.

## Key code locations

| Area | Location |
|------|----------|
| Dashboard chat | `app/controllers/dashboard/ai_controller.rb` |
| Intent + follow-up | `app/services/ai/followups/intent_resolver.rb`, `intent_detector.rb` |
| Planning | `app/services/ai/performance/request_planner.rb`, `app/services/ai/router.rb` |
| Orchestration | `app/services/ai/orchestration/constrained_runner.rb` |
| Tools | `app/services/ai/tools/executor.rb`, `registry.rb`, `app/services/ai/tools/*.rb` |
| Retrieval | `app/services/ai/performance/cached_retrieval_service.rb`, `app/services/ai/rag/retrieval_service.rb` |
| Memory | `app/services/ai/conversation/memory_budgeter.rb` |
| Policy | `app/services/ai/policy/engine.rb`, `authorization.rb` |
| Audit | `app/services/ai/audit_trail/writer.rb`, `record_builder.rb` |
| Resilience | `app/services/ai/resilience/coordinator.rb` |
| Replay | `app/services/ai/replay/request_replayer.rb`, `replay_input_builder.rb` |
