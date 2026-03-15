# AI Debugging and Replay

How to inspect AI request audits, run replay, and use metadata to investigate issues.

## Inspecting ai_request_audits

- **Model**: `AiRequestAudit` stores one record per AI request. No prompts or secrets; only metadata (request_id, endpoint, merchant_id, agent_key, composition, tool_used, tool_names, latency_ms, execution_plan, policy flags, etc.).
- **List**: Dev route `ai_audits`. Use **QueryBuilder** filters: date range (`from`, `to`), `merchant_id`, `agent_key`, `composition_mode`, `degraded_only`, `fallback_only`, `policy_blocked_only`, `tool_used`, `request_id`, `failed_only`, `high_latency_only`, `min_latency_ms`.
- **Detail**: Dev route `ai_audits/:id`. **DetailPresenter** groups safe fields into sections: request, context, parsing, execution_plan, tool_usage, orchestration, retrieval, memory, composition, policy, resilience, timing. Use this to see why a request took the path it did and whether policy or resilience intervened.

**Useful fields when investigating**:
- `execution_mode`, `retrieval_skipped`, `memory_skipped`, `retrieval_budget_reduced` → what the planner decided.
- `tool_used`, `tool_names`, `orchestration_used`, `orchestration_step_count` → deterministic path vs agent path.
- `authorization_denied`, `tool_blocked_by_policy`, `followup_inheritance_blocked`, `policy_reason_code` → policy blocks.
- `fallback_used`, `degraded`, `failure_stage`, `fallback_mode` → resilience path.
- `parsed_entities`, `parsed_intent_hints` → what intent/follow-up resolution produced (used by replay).

## How replay works

- **Entry**: From audit detail page, POST to replay action. **RequestReplayer** is called with `audit_id` and optional `request_id`.
- **Input build**: **ReplayInputBuilder** reads the audit. Replay is **possible only if**:
  - Audit has `merchant_id`.
  - Audit represents a **tool path**: `tool_used?` and `tool_names` present.
  - For the first tool in `tool_names`, args can be reconstructed from `parsed_entities` and `parsed_intent_hints` (e.g. payment_intent_id, transaction_id, from/to for ledger).
- **Re-run**: Replayer calls **ConstrainedRunner** with the reconstructed `message` and `resolved_intent` (same merchant, new request_id). No agent, no RAG, no memory—only the deterministic tool path.
- **Compare**: **DiffBuilder** compares original audit summary vs replayed run summary on a fixed set of keys (agent_key, composition_mode, tool_used, tool_names, orchestration_used, orchestration_step_count, success, policy flags, execution_mode, etc.). **ReplayResult** holds differences and matched flags (path, policy, tool usage, composition mode, debug metadata).

## What replay can and cannot do

**Can**:
- Re-run the **deterministic tool path** (single tool or 2-step orchestration) with the same intent and merchant.
- Compare current behavior vs historical: same tool(s), same composition mode, same policy outcome (or surface diffs if something changed).
- Help verify that a change to orchestration, tools, policy, or explanations did not break existing tool-path behavior.

**Cannot**:
- Re-run **agent/RAG path** requests (no intent stored in a replayable form; no re-execution of LLM or retrieval).
- Re-run requests that had **no tool usage** (nothing to replay).
- Reconstruct exact user message (replay uses a **synthetic message** from tool/args for ConstrainedRunner).
- Guarantee identical tool **data** (e.g. ledger totals) if underlying data changed; replay compares **metadata and path**, not raw response bodies.

## Comparing current vs historical path decisions

- After replay, the UI shows **ReplayResult**: `differences` (list of { field, original, replayed }), and matched flags.
- **DiffBuilder.COMPARABLE_KEYS** define what is compared. If `matched_path` is false, execution_mode or composition_mode changed. If `matched_policy_decisions` is false, authorization_denied or tool_blocked_by_policy changed. Use `differences` to see exact original vs replayed values.
- **Replay does not** re-run the planner or intent resolver for the original message; it only re-runs ConstrainedRunner with the reconstructed intent. So “would the planner choose the same path today?” is not answered by replay—only “given this intent, does the tool path behave the same?”.

## Internal metadata most useful when investigating

| Goal | Where to look |
|------|----------------|
| Why tool path vs agent path? | Audit: `intent` (not stored directly; infer from `tool_used` + `tool_names` + `parsed_entities`/`parsed_intent_hints`). Execution plan: `execution_mode`. |
| Why was retrieval/memory skipped? | Audit: `execution_plan_metadata` (reason_codes, retrieval_skipped, memory_skipped). Agent definition: supports_retrieval, supports_memory. |
| Why was tool blocked? | Audit: `authorization_denied`, `tool_blocked_by_policy`, `policy_reason_code`. Policy::Authorization. |
| Did replay match? | ReplayResult: `matched_path`, `matched_policy_decisions`, `matched_tool_usage`, `differences`. |
| What was the composition? | Audit: `composition_mode`, `deterministic_explanation_used`, `explanation_type`, `explanation_key`. |

## Replay flow summary

```
  Audit (tool_used?, tool_names, merchant_id, parsed_entities, parsed_intent_hints)
        │
        ▼
  ReplayInputBuilder.call(audit)  →  possible? (tool + reconstructable args)
        │
        ├── no  → ReplayResult(replay_possible: false, reason_codes: ['no_tool_usage'|…])
        │
        └── yes → ConstrainedRunner.call(message: synthetic, resolved_intent: reconstructed)
                        │
                        ▼
                  DiffBuilder(original_summary, replay_summary)  →  differences + matched flags
                        │
                        ▼
                  ReplayResult(replay_possible: true, differences, matched_*, …)
```
