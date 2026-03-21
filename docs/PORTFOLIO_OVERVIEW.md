# Portfolio overview

**Mini Payment Gateway** is a Rails 7.2 **service-oriented monolith** that models a merchant-scoped payment platform: REST API, dashboard, payment lifecycle (authorize → capture → void/refund), ledger, idempotency, inbound/outbound webhooks, audit logging, and an integrated **AI assistant** (deterministic tools, RAG over internal docs, policy, orchestration, observability, replay).

**Audience:** engineers evaluating architecture, correctness, and operational maturity—not a CRUD tutorial.

---

## What this project is

| Dimension | Reality |
|-----------|---------|
| **Domain** | Multi-tenant payment gateway: merchants, customers, payment intents, transactions, ledger entries |
| **API** | Versioned REST under `/api/v1`, `X-API-KEY` auth (BCrypt-hashed keys) |
| **Processor** | **Simulated by default** (`PAYMENTS_PROVIDER=simulated`); optional **Stripe test mode** via adapter ([PAYMENT_PROVIDER_SANDBOX.md](PAYMENT_PROVIDER_SANDBOX.md)) |
| **AI** | Optional: requires `GROQ_API_KEY` for live LLM; CI uses stubs—no external calls in tests |

Internal domain stays **provider-agnostic**: adapters return `ProviderResult`; services own state, ledger, and idempotency.

---

## Why this project matters (engineering value)

- **Payment semantics:** State machine (created → authorized → captured / canceled / failed), not “update a row.” Ledger writes on capture/refund only; authorize/void do not create charge ledger entries—aligned with real gateways.
- **Correctness under retries:** Idempotent mutation APIs with stored responses; dedicated invariant specs (`spec/invariants/payments/`) for financial and transition rules.
- **Webhooks:** Inbound signature verification via active provider adapter; outbound merchant delivery with retries; duplicate inbound events mitigated via `provider_event_id` where applicable.
- **Multi-tenancy:** Merchant scoping on queries and AI tools; adversarial tests for cross-tenant denial.
- **AI in a real domain:** Tools call the same models/services as the API; RAG grounds answers in versioned `docs/`; policy and contracts keep behavior testable and auditable.
- **Operability:** AI request audits, replay/debug flows, analytics/health dev surfaces, CI jobs split by concern ([AI_CI_QUALITY_GATES.md](AI_CI_QUALITY_GATES.md)).
- **Security & performance:** Threat model and security review docs; rate limiting; load/perf harness ([LOAD_AND_PERFORMANCE_TESTING.md](LOAD_AND_PERFORMANCE_TESTING.md)).

---

## Key technical highlights (scannable)

- Multi-tenant Rails monolith with explicit service boundaries (`AuthorizeService`, `CaptureService`, etc.)
- `Payments::ProviderRegistry` + adapter pattern (`simulated` / `stripe_sandbox`)
- Idempotent payment mutations + `IdempotencyRecord` fingerprinting
- Ledger with signed conventions (charges positive, refunds negative)
- Inbound webhook verification + normalized events; outbound `WebhookDeliveryJob`
- AI: deterministic tools (merchant-scoped), hybrid RAG (keyword + optional pgvector), orchestration, policy engine
- `AiRequestAudit` trail; replayable diagnostics; contract tests for stable payloads
- CI: AI contracts, scenarios, adversarial, policy, internal tooling; full RSpec suite
- C4 + sequence docs; payment invariant tests; security review and threat model

---

## Production-like qualities (not a toy)

| Area | Where it shows up |
|------|-------------------|
| Rate limiting | API request stats / limits ([SECURITY.md](SECURITY.md), [API_RATE_LIMITING.md](API_RATE_LIMITING.md)) |
| Idempotency | Payment + refund endpoints |
| Audit | `AuditLog` (payments), `AiRequestAudit` (AI) |
| Replay / debug | Dev AI audit replay, playground ([AI_DEBUGGING_AND_REPLAY.md](AI_DEBUGGING_AND_REPLAY.md)) |
| Policy | Tool authorization, merchant isolation |
| CI gates | See [AI_CI_QUALITY_GATES.md](AI_CI_QUALITY_GATES.md) |
| Contracts | `spec/ai/contracts/`, payment invariants |
| Adversarial | `spec/ai/adversarial_scenarios_spec.rb` |
| Health | AI health endpoints / pages |
| Docs corpus | Versioned sections for RAG; optional embeddings |
| Deployment safety | [AI_DEPLOYMENT_AND_RELEASE_SAFETY.md](AI_DEPLOYMENT_AND_RELEASE_SAFETY.md), [DEPLOYMENT.md](DEPLOYMENT.md) |
| Security | [SECURITY_REVIEW.md](SECURITY_REVIEW.md), [THREAT_MODEL.md](THREAT_MODEL.md) |

---

## Design trade-offs and lessons learned

| Trade-off | Choice | Rationale |
|-----------|--------|-----------|
| **Monolith vs microservices** | Monolith-first | Shared transactions, simpler consistency; horizontal scaling not the goal here. |
| **Simulated vs real processor** | Default simulated | Deterministic dev/test/CI; Stripe optional for realistic integration. |
| **Deterministic tools vs LLM** | Both | Tools for structured queries (fast, testable); LLM + RAG for explanation and follow-ups. |
| **AI safety** | Strict tenant checks | Policy and `allow_record?` over convenience; cross-tenant leakage is a test failure. |
| **RAG quality** | Docs-bound | Grounding in repo `docs/`; quality depends on corpus maintenance and optional vectors. |
| **Sync vs async** | Jobs for webhooks/delivery | Core API path synchronous; heavy work offloaded where appropriate. |
| **Internal tooling** | Dev dashboards + analytics | Replay and audits reduce debugging time without exposing secrets in production chat. |

### What I would improve next (honest)

- Broader automated integration tests against Stripe test mode (optional, gated).
- More operational runbooks and on-call playbooks if this were production.
- Further hardening of webhook idempotency across all event types.
- Optional: extract high-risk paths to separate deployable units only if scale demands it.

---

## Where to go next

| Goal | Document |
|------|----------|
| Fast architecture picture | [PROJECT_AT_A_GLANCE.md](PROJECT_AT_A_GLANCE.md) |
| Demo walkthrough (timing + paths) | [INTERVIEW_DEMO_GUIDE.md](INTERVIEW_DEMO_GUIDE.md) |
| Detailed demo steps | [DEMO_SCRIPT.md](DEMO_SCRIPT.md) |
| Deep design | [SYSTEM_DESIGN_SUMMARY.md](SYSTEM_DESIGN_SUMMARY.md), C4 docs |
| Resume / LinkedIn text | [PROJECT_BLURBS.md](PROJECT_BLURBS.md) |

---

## Accuracy note

- **Simulated processor** uses probabilistic success/failure for some paths; **not** production card processing.
- **AI** features require configuration; tests do not call Groq.
- **Stripe** is real API only when `PAYMENTS_PROVIDER=stripe_sandbox` and keys are set.

Do not claim PCI certification or production payment volume—this is a **realistic engineering codebase** for learning and demonstration.
