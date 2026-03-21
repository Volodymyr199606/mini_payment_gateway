# System design summary (entry point)

**Mini Payment Gateway** — Rails 7.2 monolith: payment lifecycle API + dashboard, webhooks, ledger, idempotency, audit logs, and an integrated AI platform (agents, tools, RAG, memory, policy, observability).

**Portfolio / interviews:** For a concise narrative, demo timing, and resume blurbs, see [PORTFOLIO_OVERVIEW.md](PORTFOLIO_OVERVIEW.md), [INTERVIEW_DEMO_GUIDE.md](INTERVIEW_DEMO_GUIDE.md), and [PROJECT_BLURBS.md](PROJECT_BLURBS.md).

## Quick facts

| Aspect | Implementation |
|--------|----------------|
| API | `GET/POST` under `/api/v1` — `X-API-KEY` (BCrypt) |
| Dashboard | `/dashboard/*` — session auth |
| Tenancy | `merchant_id` everywhere |
| DB | PostgreSQL (+ optional `pgvector` for embeddings) |
| Cache | `Rails.cache` — retrieval/memory/tool caching, AI rollup |
| Jobs | `ApplicationJob` — `WebhookDeliveryJob`, `Ai::*` jobs |
| Payment processor | `PAYMENTS_PROVIDER`: `simulated` (default) or `stripe_sandbox` — see [PAYMENT_PROVIDER_SANDBOX.md](PAYMENT_PROVIDER_SANDBOX.md) |
| AI LLM | Groq when enabled (`GROQ_API_KEY`); tests stub |
| Inbound webhooks | `POST /api/v1/webhooks/processor` — verified via **active payment provider adapter** |

## C4-style package (this repo)

1. [C4_CONTEXT.md](C4_CONTEXT.md) — who/what touches the system  
2. [C4_CONTAINER.md](C4_CONTAINER.md) — logical runtime layers  
3. [C4_COMPONENTS.md](C4_COMPONENTS.md) — main modules and contracts  

## Sequence-style flows (step-by-step)

1. [SEQUENCES_PAYMENT_FLOW.md](SEQUENCES_PAYMENT_FLOW.md) — authorize, capture, refund, void  
2. [SEQUENCES_AI_FLOW.md](SEQUENCES_AI_FLOW.md) — dashboard deterministic vs agent path (API path summarized)  
3. [SEQUENCES_WEBHOOK_FLOW.md](SEQUENCES_WEBHOOK_FLOW.md) — verify → persist → deliver  

## Deep dives (already in repo)

| Topic | Doc |
|-------|-----|
| Payment lifecycle semantics | [PAYMENT_LIFECYCLE.md](PAYMENT_LIFECYCLE.md) |
| Security / auth | [SECURITY.md](SECURITY.md) |
| AI agents & RAG | [AI_AGENTS.md](AI_AGENTS.md) |
| AI request narrative | [AI_REQUEST_FLOW.md](AI_REQUEST_FLOW.md) |
| Provider adapters | [PROVIDER_ADAPTER_ARCHITECTURE.md](PROVIDER_ADAPTER_ARCHITECTURE.md) |
| CI / quality gates | [AI_CI_QUALITY_GATES.md](AI_CI_QUALITY_GATES.md) |
| Deploy | [DEPLOYMENT.md](DEPLOYMENT.md) |

## Design posture (honest)

- **Monolith-first:** simpler transactions and shared models; scale-out is not the primary goal of this codebase.
- **Two AI paths:** cheap deterministic tools/orchestration when applicable; LLM+RAG otherwise (dashboard is richer than API chat).
- **Auditability:** payment `AuditLog`, AI `AiRequestAudit`, webhook `WebhookEvent` — different contracts, all intentional.

For **trade-offs** and **safe-to-change** guidance, see the end of [C4_COMPONENTS.md](C4_COMPONENTS.md).
