# AI Interface Contracts

Internal contracts and versioning for the AI system boundaries. Use these when building or consuming payloads across layers.

## Overview

- **Purpose**: Stabilize internal AI interfaces so changes are safer and easier to reason about.
- **Scope**: Parsing, planning, tools, retrieval, composition, policy, audit, and debug payloads.
- **Versioning**: `contract_version` or `schema_version` is set where payloads are serialized, persisted, or consumed by multiple layers.

## Contract Objects and Versions

| Contract | Location | Version constant | Used for |
|----------|----------|------------------|----------|
| ParsedIntent | Ai::Contracts::ParsedIntent | PARSED_INTENT_VERSION | IntentDetector output: tool_name, args |
| IntentResolution | Ai::Contracts::IntentResolution | INTENT_RESOLUTION_VERSION | IntentResolver output: intent, followup |
| ExecutionPlan | Ai::Performance::ExecutionPlan | EXECUTION_PLAN_VERSION | RequestPlanner output; to_audit_metadata, to_h |
| ToolResult | Ai::Contracts::ToolResult | TOOL_RESULT_VERSION | Executor output: success, tool_name, data, error, metadata, latency_ms |
| RunResult | Ai::Orchestration::RunResult | RUN_RESULT_VERSION | ConstrainedRunner output; to_h |
| RetrievalResult | Ai::Contracts::RetrievalResult | RETRIEVAL_RESULT_VERSION | RetrievalService/ContextBudgeter: context_text, citations, context_truncated |
| ComposedResponse | Ai::Contracts::ComposedResponse | COMPOSED_RESPONSE_VERSION | ResponseComposer output; composition.contract_version |
| Policy::Decision | Ai::Policy::Decision | — | Policy checks; to_h |
| AuditPayload | Ai::Contracts::AuditPayload | AUDIT_PAYLOAD_VERSION | RecordBuilder output; schema_version in hash |
| DebugPayload | Ai::Contracts::DebugPayload | DEBUG_PAYLOAD_VERSION | EventLogger.build_debug_payload; schema_version in hash |

## Stable Field Names

Use these names consistently across services:

- **Request/context**: request_id, endpoint, merchant_id, agent_key, retriever_key
- **Composition**: composition_mode, used_tool_data, used_doc_context, used_memory_context, citations_count, deterministic_fields_used
- **Tool**: tool_used, tool_names, tool_name, data, success, error, error_code
- **Timing**: latency_ms
- **Flags**: fallback_used, citation_reask_used, memory_used, summary_used, authorization_denied, tool_blocked_by_policy
- **Explanation**: deterministic_explanation_used, explanation_type, explanation_key
- **Orchestration**: orchestration_used, orchestration_step_count, orchestration_halted_reason
- **Execution plan**: execution_mode, retrieval_skipped, memory_skipped, orchestration_skipped, retrieval_budget_reduced, reason_codes

## Where Versions Are Set

- **ExecutionPlan**: `to_audit_metadata` and `to_h` include `contract_version`.
- **RunResult**: `to_h` includes `contract_version`.
- **ResponseComposer**: `composition` includes `contract_version`.
- **RecordBuilder**: output hash includes `schema_version` (audit payload).
- **EventLogger.build_debug_payload**: returned hash includes `schema_version`.

## Validation

- Contract POROs (e.g. ToolResult, ParsedIntent) may call `validate!` in development/test to check required fields.
- In production, fail safely where needed; do not raise on malformed payloads from external callers unless necessary.

## Serialization

- **to_h**: All contract objects support `to_h` for stable serialization.
- **from_h**: ParsedIntent, IntentResolution, ToolResult, RetrievalResult, ComposedResponse, AuditPayload, DebugPayload support `from_h` for round-trip or parsing.

## Evolving a Contract

1. **Add optional fields**: Add new keys with safe defaults; consumers that ignore them remain valid.
2. **Change semantics of existing field**: Bump the contract/schema version; document the change here and in code.
3. **Remove or rename field**: Introduce a new version and support both in readers until old version is deprecated.
4. **Audit/debug**: When adding columns to ai_request_audits or changing debug shape, bump AUDIT_PAYLOAD_VERSION or DEBUG_PAYLOAD_VERSION and update RecordBuilder/Writer or EventLogger.

## Integration Points

- **RequestPlanner** returns ExecutionPlan (Struct); no change to callers.
- **Executor** returns a hash; wrap with ToolResult.from_h for validation/serialization if needed.
- **ConstrainedRunner** returns RunResult; use RunResult#to_h for audit/debug.
- **RetrievalService** returns a hash; wrap with RetrievalResult.from_h if needed.
- **ResponseComposer** returns a hash with composition.contract_version; ComposedResponse.from_h for formal contract.
- **RecordBuilder** output includes schema_version; Writer persists only columns that exist (schema_version is optional column).
- **EventLogger.build_debug_payload** returns hash with schema_version; DebugPayload.from_h for formal contract.
