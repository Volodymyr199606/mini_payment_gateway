# AI Operations

Operational guidance for the internal AI platform: where to look, what to inspect, and how to debug regressions.

## AI analytics dashboard

- **URL**: Dev route `ai_analytics` (e.g. `/dev/ai_analytics`). **Dev/test only**; returns 404 in production.
- **Backing**: `Dev::AiAnalyticsController#index` → `Ai::Analytics::DashboardQuery` (scopes `ai_request_audits` by period and optional `merchant_id`) → `Ai::Analytics::MetricsBuilder`.
- **What it shows**: Aggregated metrics over the selected period: total requests, avg latency, fallback rate, tool usage rate, policy-blocked rate, breakdown by agent, composition mode, tool usage, fallback reasons, policy denials, follow-up stats, latency distribution, citation/memory stats, and recent requests.
- **No prompts or secrets**: All data comes from persisted audit fields only.

**When to use**: Check overall health, spot spikes in fallback or policy denials, see which agents/tools are used, and identify high-latency or failed requests.

## AI health / SLO page

- **URL**: Dev route `ai_health` (e.g. `/dev/ai_health`). **Dev/test only.**
- **Backing**: `Dev::AiHealthController#show` → `Ai::Monitoring::HealthReporter` (with optional `merchant_id`) and `Ai::Rag::Corpus::StateService`.
- **HealthReporter**: Uses `MetricsQuery` per time window (15m, 1h, 24h), `SloEvaluator` for status (healthy/warning/unhealthy), and `AnomalyDetector` for recent anomalies. Returns a `HealthReport` (overall status, metric statuses, recent anomalies, time_windows).
- **Corpus state**: RAG corpus version and related state (StateService). Useful to confirm corpus is loaded and version matches expectations.

**When to use**: Verify SLO status, see which time windows or metrics are failing, and confirm RAG corpus is present and versioned.

## Audit drill-down tooling

- **URL**: Dev routes `ai_audits` (list), `ai_audits/:id` (detail). **Dev/test only.**
- **List**: `Dev::AiAuditsController#index` → `Ai::AuditTrail::QueryBuilder.call(params, limit: 100)`. Supports filters: date range, merchant_id, agent_key, composition_mode, degraded_only, fallback_only, policy_blocked_only, tool_used, request_id, failed_only, high_latency_only, min_latency_ms.
- **Detail**: `#show` loads `AiRequestAudit` by id and presents it via `Ai::AuditTrail::DetailPresenter`. Presents only safe persisted fields, grouped (request, context, parsing, execution_plan, tool_usage, orchestration, retrieval, memory, composition, policy, resilience, timing). No prompts or secrets.

**When to use**: Investigate a specific request (e.g. from analytics or support). Use filters to find policy-blocked, degraded, or high-latency requests.

## Replayable request debugging

- **URL**: From audit detail, POST to `replay_ai_audit_path(audit)` (e.g. `ai_audits/:id/replay`). **Dev/test only.**
- **Behavior**: `Ai::Replay::RequestReplayer` builds input from the audit (only when replay is possible: tool path with known tool and reconstructable args). Re-runs **ConstrainedRunner** with that input and compares outcome to original (DiffBuilder). Result is flashed and shown on the audit detail page.
- **Limitations**: Replay is only for **deterministic tool path** requests. Agent/RAG path and requests without tool usage cannot be replayed. See [AI_DEBUGGING_AND_REPLAY.md](AI_DEBUGGING_AND_REPLAY.md).

**When to use**: After a change to orchestration, tools, or policy, replay a few historical tool requests to confirm behavior matches or to compare diffs.

## Cache and corpus versioning

- **Tool/retrieval/memory cache**: `Ai::Performance::CachePolicy` and `CacheKeys`. TTLs and categories (retrieval, ledger, merchant_account, memory, tool_other). Cache is bypassed when `AI_DEBUG=true` or `AI_CACHE_BYPASS=true`. Tool cacheability comes from tool registry definition (`cacheable?`).
- **RAG corpus**: Versioned via `Ai::Rag::Corpus::StateService`. Corpus version can be stored on audit records (`corpus_version`) for traceability. Embeddings/refresh: see runbook `docs/runbooks/AI_EMBEDDINGS_RUNBOOK.md` if present.

**When to use**: If responses look stale, check bypass env vars and TTLs. If RAG answers are wrong or missing, check corpus version and that docs are indexed.

## Resilience and fallback behavior

- **On exception**: `Dashboard::AiController` (and similar) rescues, calls `Resilience::Coordinator.plan_fallback` with inferred failure stage (generation, retrieval, tool, orchestration, memory, streaming, audit_debug, unknown), then builds a safe response via `build_safe_response`. User gets a generic message; audit can record degraded/failure_stage/fallback_mode.
- **Safe messages**: Defined in `Ai::Resilience::Coordinator::SAFE_MESSAGES`; never expose internals.

**When to use**: If users report “something went wrong” or a generic message, check audits for `degraded`, `failure_stage`, `fallback_mode` to see where the pipeline failed.

## What to inspect when AI behavior regresses

1. **Confirm path**: Check audit for `execution_mode`, `tool_used`, `orchestration_used`, `composition_mode`. Was it tool path or agent path? If tool, which tool(s)?
2. **Policy**: Look at `authorization_denied`, `tool_blocked_by_policy`, `followup_inheritance_blocked`, `policy_reason_code`. Policy blocks are intentional; if unexpected, review Policy::Authorization and Engine.
3. **Execution plan**: `execution_plan_metadata` (or execution_mode, retrieval_skipped, memory_skipped, retrieval_budget_reduced). Did the planner skip retrieval or memory for this agent? Check agent definition (supports_retrieval, supports_memory).
4. **Retrieval**: `retrieved_sections_count`, `citations_count`, `corpus_version`. If zero sections, check RAG and AgentDocPolicy for that agent.
5. **Fallback**: `fallback_used`, `degraded`, `failure_stage`. If true, something failed and resilience kicked in; check logs for the original exception.
6. **Replay**: For tool-path requests, use replay to compare current vs historical outcome (same intent, same merchant). Diffs show what changed in tool/explanation/orchestration.

## Common operational questions

| Question | Where to look |
|----------|----------------|
| Why did this request use a fallback message? | Audit: `fallback_used`, `degraded`, `failure_stage`, `error_class`, `error_message`. Logs around the request_id. |
| Why was retrieval skipped? | Audit: `execution_plan_metadata` (reason_codes, retrieval_skipped). Agent definition: `supports_retrieval?`. Or intent was present → deterministic path. |
| Why was tool X blocked? | Audit: `tool_blocked_by_policy`, `authorization_denied`, `policy_reason_code`. Policy::Authorization (allow_tool?, allow_record?). |
| Why did orchestration not run? | No intent (IntentResolver), or policy denied (allow_orchestration?). Audit: intent vs tool_used/orchestration_used. |
| Is the corpus up to date? | Dev health page: corpus state. Audit: `corpus_version` on recent requests. |
| How do I test a change without affecting production? | Use dev playground and replay; filter audits by merchant_id and time. |
