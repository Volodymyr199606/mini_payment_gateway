# AI Safety and Policy

Trust boundaries, policy responsibilities, and rules that keep the AI subsystem safe and tenant-isolated.

## Merchant-scoped authorization

- Every AI request is tied to a **merchant** (from dashboard session or API auth). `merchant_id` is in the context for the whole pipeline.
- **Policy::Authorization** is the central place for merchant-scoped checks. It receives `context` (including `merchant_id`) and validates:
  - **allow_tool?**: Merchant present; tool name in `Tools::Registry`. Ledger/merchant_account are implicitly scoped by context; entity tools (payment_intent, transaction, webhook_event) validate ownership **after** fetch via **allow_record?**.
  - **allow_record?**: Given a fetched record, verifies the record’s owner (e.g. `merchant_id` on PaymentIntent, Transaction, WebhookEvent) equals context `merchant_id`. Denies with a safe message (no leak of existence).
  - **allow_entity_reference?**: Before running a tool, can check that an entity id exists and is owned by the merchant (optional guard).
  - **allow_followup_inheritance?**: When reusing an entity or time range from a follow-up, revalidates that the entity is owned by the merchant (no cross-tenant reuse).

**Rule**: Deterministic product/account data must never cross tenant boundaries. All tool results that include records are gated by `allow_record?` (or equivalent) after fetch.

## Policy engine responsibilities

- **Ai::Policy::Engine** wraps Authorization and adds:
  - **allow_orchestration?**: Merchant present and intent (or resolved_intent) present. No intent → no orchestration.
  - **allow_memory_reuse?**: Merchant present (memory is already session/merchant-scoped by construction).
  - **allow_followup_inheritance?**: Delegates to Authorization with entity_type/entity_id.
  - **allow_source_composition?**: Merchant present; rejects composition that would include unsafe source types (e.g. raw_payload, internal).
  - **allow_debug_exposure?**: Only when AI_DEBUG is enabled and payload does not contain prompt or api_key.
  - **allow_deterministic_data_exposure?**, **allow_docs_only_fallback?**: Merchant present; deterministic data exposure can delegate to Authorization for composed data.

**Rule**: The engine is the single governance layer for “is this allowed?”. Controllers and services call the engine; they do not bypass it for security-sensitive decisions.

## Follow-up inheritance safety

- Follow-up resolution can inherit **entity** (e.g. payment_intent_id from prior message) or **time range** from conversation.
- Before using inherited entity ids in a tool, **allow_followup_inheritance?** is used: entity type and id are checked against the current merchant (e.g. PaymentIntent belongs to merchant). Prevents one tenant from reusing another tenant’s entity reference.

## Tool restrictions

- **Registry**: Only tools in `Ai::Tools::Registry` are allowed. Unknown tool → deny (REASON_TOOL_NOT_ALLOWED).
- **Read-only**: All tools are required to be read-only (validated at boot in dev/test). No create/update/delete from the AI path.
- **Executor**: Before running a tool, Executor calls `Policy::Engine#allow_tool?`. On deny, returns access_denied and does not run the tool. Tool implementations use `allow_record?` for any fetched record before returning it.

## Orchestration limits

- **ConstrainedRunner**: Max **2** steps. No recursion, no loops. Second step only when FOLLOW_UP_RULES allow (e.g. get_transaction → get_payment_intent with payment_intent_id from step 1).
- **Intent required**: Orchestration runs only when intent is present (from IntentResolver or IntentDetector). Policy **allow_orchestration?** also requires intent. No intent → no orchestration.

## Debug exposure rules

- Debug payload (e.g. for dashboard when AI_DEBUG is on) is built by **EventLogger.build_debug_payload** and gated by **allow_debug_exposure?**.
- **Must not contain**: prompt text, API keys, or other secrets. Policy explicitly checks for prompt/api_key in payload and denies if present.
- Registry metadata (agents/tools list with safe fields) can be included for internal tooling; no class internals or config that could leak across tenants.

## No-write AI constraint

- The AI subsystem **must not** create, update, or delete business records (payment intents, transactions, refunds, etc.). Tools only **read** data. This is enforced by:
  - Tool registry validation: all tools must have `read_only: true` in their definition.
  - No tool in the registry is implemented to perform writes. Adding a write tool would require a deliberate design change and security review.

## Trust boundaries and source-of-truth

| Source | Role | Trust boundary |
|--------|------|----------------|
| **Deterministic product data** | Tool results (ledger, payment intent, transaction, webhook, merchant account). | Always scoped by merchant_id; policy validates ownership before exposure. Single source of truth for “what the system says” about that data. |
| **Docs-derived knowledge** | RAG context from `docs/*.md` (and indexed content). | Used only to generate answers; not used to change data. Agent instructions forbid inventing numbers; for “how much” the tool provides data. |
| **Conversation memory** | Summary + recent messages per session. | Built per merchant/session; never shared across tenants. Policy allow_memory_reuse? is redundant with construction but documents the boundary. |
| **Policy-enforced restrictions** | allow_tool?, allow_record?, allow_orchestration?, allow_followup_inheritance?. | All data access and reuse flows through policy. No bypass for “convenience.” |

**Summary**: Deterministic data is the source of truth for product/account facts. Docs and memory are inputs to the agent’s answer only. Policy ensures that only the owning merchant can see or reuse their data and that no write path exists from the AI pipeline.
