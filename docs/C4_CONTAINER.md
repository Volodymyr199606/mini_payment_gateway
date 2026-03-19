# C4 Level 2 — Container view (logical)

The application is a **single Rails process** (plus Puma workers in production). Containers here are **logical** boundaries: clear module ownership and I/O surfaces, not separate microservices.

## Container diagram (Mermaid — flowchart style)

```mermaid
flowchart TB
  subgraph Clients
    API[API clients]
    WEB[Browser / dashboard]
    DEV[Dev tooling users]
  end

  subgraph RailsMonolith["Rails monolith (Mini Payment Gateway)"]
    REST[REST API layer\nApi::V1::*Controller]
    DASH[Dashboard layer\nDashboard::*Controller]
    DEVCTL[Dev controllers\nDev::* (constraint)]
    SVC[Domain & payment services\nAuthorize/Capture/Void/Refund\nLedger, Idempotency, Webhooks]
    PAYPROV[Payment provider adapters\nPayments::Providers::*]
    AI[AI subsystem\napp/services/ai/**]
    JOBS[Active Job adapters\nWebhookDeliveryJob, Ai::*]
  end

  PG[(PostgreSQL)]
  CACHE[(Rails.cache)]
  EXT_STRIPE[Stripe API\noptional]
  EXT_GROQ[Groq API\noptional]
  EXT_EMBED[Embedding API\noptional]
  MERCH_URL[Merchant webhook URL\noptional]

  API --> REST
  WEB --> DASH
  DEV --> DEVCTL

  REST --> SVC
  DASH --> SVC
  REST --> PAYPROV
  DASH --> PAYPROV
  SVC --> PG
  AI --> PG
  AI --> CACHE
  PAYPROV --> EXT_STRIPE
  AI --> EXT_GROQ
  AI --> EXT_EMBED
  SVC --> JOBS
  AI --> JOBS
  JOBS --> CACHE
  JOBS --> MERCH_URL
```

## Container table

| Container | Code home | Protocol / surface |
|-----------|-----------|-------------------|
| **REST API** | `app/controllers/api/v1/` | JSON; `X-API-KEY`; `ApiAuthenticatable` |
| **Dashboard** | `app/controllers/dashboard/` | HTML + JSON for AI chat; session |
| **Dev / internal AI tooling** | `app/controllers/dev/` | HTML/JSON; **404 in production** via `DevRoutesConstraint` |
| **Payment & domain services** | `app/services/*.rb`, `concerns/` | Ruby calls; DB transactions |
| **Payment provider integration** | `app/services/payments/**` | HTTP to Stripe when `stripe_sandbox`; else in-process simulate |
| **AI subsystem** | `app/services/ai/**` | Ruby; optional Faraday to Groq/embeddings |
| **Background jobs** | `app/jobs/` | Async delivery, AI summary, metrics rollup |
| **PostgreSQL** | `db/`, ActiveRecord | System of record |
| **Rails.cache** | `config/environments/*` | Retrieval/memory/tool cache; AI rollup summaries |

## Request paths (high level)

1. **Payment API:** `Api::V1::*` → services → DB → (optional) enqueue `WebhookDeliveryJob`
2. **Dashboard payment:** `Dashboard::PaymentIntentsController` → same services
3. **AI dashboard:** `Dashboard::AiController#chat` → follow-up + planner + orchestration **or** retrieval + agent
4. **AI API:** `Api::V1::Ai::ChatController` — **simpler path:** `Router` → `CachedRetrievalService` → agent (no `ConstrainedRunner` in controller)
5. **Inbound webhook:** `Api::V1::WebhooksController#processor` → `Payments::ProviderRegistry.current` verify/normalize → `WebhookEvent`

## Optional / flag-gated behavior (explicit)

| Capability | How toggled |
|------------|-------------|
| Graph-expanded RAG | `AI_CONTEXT_GRAPH_ENABLED` (via `Ai::Config::FeatureFlags`) |
| Hybrid vector RAG | `AI_VECTOR_RAG_ENABLED` + pgvector + embeddings |
| AI streaming | `AI_STREAMING_ENABLED` + `stream` param on dashboard chat |
| AI debug payload | `AI_DEBUG` |
| Real Stripe sandbox | `PAYMENTS_PROVIDER=stripe_sandbox` + keys (see initializer validation) |
