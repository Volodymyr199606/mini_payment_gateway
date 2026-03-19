# Mini Payment Gateway — System Design & Architecture

**Version:** 1.0  
**Rails:** 7.2 | **Ruby:** ≥3.1 | **Database:** PostgreSQL (+ optional pgvector)  
**Modeled after:** Braintree-style payment lifecycle with an integrated AI assistant layer

---

## Part 1 — What Is Done Overall

### Scope

- **Payment platform (simulated):** Full Braintree-style lifecycle: customers, payment methods, payment intents, authorize → capture → void/refund, idempotency, ledger (charge/refund/fee), audit logs, and outbound webhooks with signature verification. No real card processor; all processing is simulated in-app.
- **Dual surface:** REST API (`/api/v1`) and merchant dashboard (HTML with Turbo/Stimulus). Shared service layer and domain model; API uses `X-API-KEY`, dashboard uses session (email/password or API key sign-in).
- **Multi-tenant isolation:** All tenant data is scoped by `merchant_id`. No cross-merchant access; API and dashboard resolve `current_merchant` and scope all queries.
- **AI subsystem:** Multi-agent chat (operational, reporting, support, security, developer, reconciliation), RAG over project docs (keyword, optional graph expansion, optional hybrid vector), deterministic tools (account, ledger summary, payment intent, transaction, webhook), constrained orchestration (up to 2 tool steps), conversation memory/summary, resilience/fallback, audit trail, streaming, guardrails, and internal tooling (playground, analytics, health, audit drill-down/replay). Config and quality gates are documented and CI-covered.
- **Operations:** Rate limiting, API request stats, payment and AI audit trails, metrics/rollup jobs, feature flags (env-driven), structured logging, Kamal-based deployment notes, and CI (including AI quality gates and non-AI spec suite).

### Not in scope (by design)

- Real payment processor integration (e.g. Braintree/Stripe).
- Generic feature-flag service or A/B framework beyond env-based AI flags.
- Separate tenant abstraction (tenancy is merchant_id everywhere).

---

## Part 2 — System Design & Architecture

### 2.1 High-Level Architecture

```
                    ┌─────────────────────────────────────────────────────────┐
                    │                    Rails monolith                        │
                    │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐  │
  Clients           │  │ REST API    │  │ Dashboard   │  │ Dev (optional)  │  │
  ───────           │  │ /api/v1     │  │ /dashboard  │  │ /dev/ai_*       │  │
  • API clients     │  │ X-API-KEY   │  │ session     │  │ constraint      │  │
  • Browsers        │  └──────┬──────┘  └──────┬──────┘  └────────┬────────┘  │
                    │         │                │                   │           │
                    │         └────────────────┼───────────────────┘           │
                    │                          ▼                                │
                    │  ┌─────────────────────────────────────────────────────┐ │
                    │  │ Controllers (API v1, Dashboard, Dev)                │ │
                    │  │ + Concerns: ApiAuthenticatable, StructuredLogging    │ │
                    │  └──────────────────────────┬──────────────────────────┘ │
                    │                             ▼                            │
                    │  ┌─────────────────────────────────────────────────────┐ │
                    │  │ Services (payment, webhooks, idempotency, ledger,     │ │
                    │  │          audit, metrics, rate limit, AI/*)           │ │
                    │  └──────────────────────────┬──────────────────────────┘ │
                    │                             ▼                            │
                    │  ┌─────────────────────┐  ┌─────────────────────────────┐ │
                    │  │ ActiveRecord models │  │ Jobs (WebhookDelivery,       │ │
                    │  │ (merchant-scoped)   │  │ AI summary, rollup, docs)   │ │
                    │  └─────────────────────┘  └─────────────────────────────┘ │
                    └─────────────────────────────────────────────────────────┘
                                          │
                    ┌─────────────────────┼─────────────────────┐
                    ▼                     ▼                     ▼
              PostgreSQL            Rails.cache           External (optional)
              ( + pgvector )         (memory/redis)        Groq, Embedding API
```

- **Single application:** One codebase serves API, dashboard, and (in dev/test) internal AI tooling. No separate API vs dashboard processes.
- **Data:** PostgreSQL is the system of record. Optional pgvector extension for RAG embeddings. Rails.cache used for retrieval/memory/tool result caching and AI rollup metrics.
- **External calls:** Outbound webhooks to merchant URLs; optional Groq (LLM) and OpenAI-compatible embedding API for AI.

---

### 2.2 Entry Points & Authentication

| Surface        | Path / constraint        | Auth                          | Purpose |
|---------------|--------------------------|-------------------------------|---------|
| REST API      | `/api/v1/*`              | `X-API-KEY` (BCrypt digest)   | Programmatic access: payments, customers, AI chat, etc. |
| Dashboard     | `/dashboard/*`           | Session (`merchant_id`); sign-in by email+password or API key | Merchant UI: overview, transactions, intents, ledger, webhooks, AI chat |
| Health       | `GET /api/v1/health`     | None                          | Liveness |
| Webhook in   | `POST /api/v1/webhooks/processor` | `X-WEBHOOK-SIGNATURE` (HMAC-SHA256) | Inbound processor events (no API key) |
| Dev tooling  | `/dev/ai_playground`, `ai_analytics`, `ai_health`, `ai_audits` | DevRoutesConstraint (dev/test only) | AI playground, analytics, health, audit list/detail/replay |

- **Multi-tenancy:** Every request that touches data resolves `current_merchant` and scopes by `merchant_id`; no shared tenant context.

---

### 2.3 Domain Model (Core Entities)

- **Merchant** — Credentials (email, password_digest, api_key_digest). Has many: customers, payment_intents, ledger_entries, webhook_events, audit_logs, idempotency_records, api_request_stats, ai_chat_sessions, ai_chat_messages, ai_request_audits.
- **Customer** — Belongs to merchant; email unique per merchant. Has many payment_methods, payment_intents.
- **PaymentMethod** — Belongs to customer; optional on PaymentIntent.
- **PaymentIntent** — Belongs to merchant, customer, optional payment_method. Status: created → authorized → captured | canceled | failed. Idempotency key unique per merchant. Has many transactions.
- **Transaction** — Belongs to payment_intent. Kind: authorize | capture | void | refund; status succeeded | failed. Has one ledger_entry; processor_ref generated.
- **LedgerEntry** — Belongs to merchant, optional payment_transaction. Entry type: charge | refund | fee.
- **WebhookEvent** — Belongs to merchant (optional). Delivery status, attempts; after_commit enqueues WebhookDeliveryJob.
- **IdempotencyRecord** — Belongs to merchant; uniqueness on (idempotency_key, endpoint).
- **AuditLog** — Belongs to merchant (optional); used by payment services (Auditable).
- **ApiRequestStat** — Belongs to merchant; per-day request/error/rate_limited counts.
- **AiChatSession** — Belongs to merchant; has many ai_chat_messages.
- **AiChatMessage** — Belongs to merchant, optional ai_chat_session; role (user/assistant), content, agent.
- **AiRequestAudit** — Belongs to merchant (optional); request_id, endpoint, agent_key, success, composition; used for observability and replay (no prompts/secrets).
- **DocSectionEmbedding** — Section-level embeddings for RAG (pgvector); optional.

**Flow:** Merchant → Customer → PaymentMethod → PaymentIntent → Transaction → LedgerEntry. Webhooks, idempotency, audit, and AI artifacts are merchant-scoped or explicitly optional merchant.

---

### 2.4 Payment Lifecycle (Simulated)

- **Authorize** — Creates transaction (authorize), updates intent to authorized; no real processor call.
- **Capture** — Creates capture transaction, creates ledger charge entry; intent → captured.
- **Void** — Void transaction; intent → canceled.
- **Refund** — Refund transaction + ledger refund (and optional fee) entry.
- **Idempotency** — Per-merchant, per-endpoint idempotency keys; duplicate requests return stored response.
- **Webhooks** — Processor events (e.g. authorized, captured) create WebhookEvent; WebhookDeliveryJob delivers to merchant URL with signature.

All payment state is in PostgreSQL; no external processor.

---

### 2.5 AI Subsystem Architecture

- **Router** — Heuristic routing from user message to agent key (reporting, security, developer, operational, reconciliation, support_faq default).
- **Agents** — Registry of agents (e.g. OperationalAgent, ReportingCalculationAgent); all inherit BaseAgent. Each agent has retrieval/memory preferences; BaseAgent builds system prompt (rules + optional Memory section + RAG context), calls GroqClient or short-circuits on low/empty context.
- **Retrieval (RAG)** — RetrievalService, behind CachedRetrievalService. Feature-flagged: GraphExpandedRetriever (seed + graph links), HybridRetriever (keyword + vector), or DocsRetriever (keyword). Corpus from project docs; optional pgvector embeddings and backfill task.
- **Tools** — Registry of deterministic tools: GetMerchantAccount, GetLedgerSummary, GetPaymentIntent, GetTransaction, GetWebhookEvent. IntentDetector, Executor, Orchestrator; policy engine for allow/orchestration.
- **Orchestration** — ConstrainedRunner: max 2 steps, follow-up rules (e.g. transaction → payment intent); uses tools and policy.
- **Memory** — ConversationContextBuilder (summary + recent messages); MemoryBudgeter formats for prompt; async SummaryRefreshEnqueuer → RefreshConversationSummaryJob (Groq).
- **Resilience** — Coordinator infers failure stage (generation, retrieval, tool, etc.) and returns safe fallback; no raw errors to client.
- **Audit** — Every AI request writes AiRequestAudit (sanitized); QueryBuilder, DetailPresenter; replay uses stored request for debugging.
- **Guardrails** — Empty retrieval guard, citation enforcement, secret-leak guard in pipeline.
- **Config** — FeatureFlags (AI_ENABLED, streaming, debug, graph, vector, orchestration, cache bypass, internal tooling); StartupValidator; runtime limits (context, memory, citations).

Controllers (dashboard and API) build context, call planner/orchestration or agent path, compose response, write audit, and optionally enqueue summary refresh.

---

### 2.6 Background Jobs

| Job                         | Role |
|-----------------------------|------|
| WebhookDeliveryJob          | Deliver WebhookEvent to merchant URL with signature; retries. |
| Ai::RefreshConversationSummaryJob | Run ConversationSummarizer (Groq) for session; enqueue after transaction commit. |
| Ai::RollupRequestAuditMetricsJob  | Aggregate AI audit metrics into cache for analytics dashboard. |
| Ai::RefreshDocsIndexJob     | Refresh in-memory docs index (keyword corpus). |
| Ai::BaseJob                 | Shared logging (log_performed, log_failed) for AI jobs. |

---

### 2.7 Security & Multi-Tenancy

- **Isolation:** All queries and associations scoped by `merchant_id`; `current_merchant` set from API key or session.
- **API:** ApiAuthenticatable; 401 on missing/invalid `X-API-KEY`. API key stored as BCrypt digest.
- **Dashboard:** Session auth; sign-in by email+password or API key (API-key sign-in requires merchant to have email and password set).
- **Webhooks in:** No API key; verification via HMAC-SHA256 (WEBHOOK_SECRET). No prompt/secret in AI audit logs.

---

### 2.8 Observability & Ops

- **Logging:** StructuredLogging; request_id (middleware + AI thread); sanitized exception logging.
- **Metrics:** ApiRequestStat per merchant (requests, errors, rate-limited); AI metrics via MetricsQuery, HealthReport, AnomalyDetector; rollup job for analytics.
- **Audit:** AuditLog for payment actions; AiRequestAudit for AI (no prompts); replay for AI debugging.
- **Feature flags:** Ai::Config::FeatureFlags (env); no generic feature-flag backend.
- **CI:** GitHub Actions — setup, AI quality gates (contracts, scenarios, adversarial, policy, internal tooling, docs, demo seed), spec_rest; PostgreSQL + pgvector; no external API calls in tests.
- **Deployment:** Kamal and deployment docs (env, jobs, production checklist).

---

### 2.9 External Integrations

| Integration     | Use | Config |
|-----------------|-----|--------|
| Payment processor | None (simulated in-app) | — |
| Groq             | LLM for chat and summary | GROQ_API_KEY, GROQ_BASE_URL, GROQ_MODEL |
| Embedding API    | Optional vector RAG      | EMBEDDING_API_KEY or OPENAI_API_KEY, EMBEDDING_BASE_URL, EMBEDDING_MODEL |
| Outbound webhooks | Merchant URLs            | Per-event; WebhookDeliveryService |

---

### 2.10 Document Index (Relevant to Design)

- **ARCHITECTURE.md** — Directory structure, service usage, high-level boundaries.
- **PAYMENT_LIFECYCLE.md** — Authorize/capture, statuses, void/refund, ledger.
- **DATA_FLOW.md**, **SEQUENCE_DIAGRAMS.md**, **DIAGRAMS.md** — Data and sequences.
- **SECURITY.md** — Auth, scoping, PCI, webhooks, rate limiting.
- **AI_AGENTS.md**, **AI_REQUEST_FLOW.md**, **AI_PLATFORM.md** — AI behavior and platform.
- **AI_INTERFACE_CONTRACTS.md**, **AI_CI_QUALITY_GATES.md** — Contracts and CI.
- **DEPLOYMENT.md** — Env, jobs, production.
- **DEMO_SCRIPT.md** — Demo flows and seeded data.

This document summarizes the current system design and architecture as implemented; for implementation details and runbooks, see the referenced docs.
