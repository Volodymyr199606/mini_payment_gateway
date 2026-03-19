# Architecture overview (C4 + sequences)

This repo documents the **implemented** Rails 7.2 monolith: a Braintree-style payment gateway with REST API, merchant dashboard, webhooks, ledger/idempotency/audit, and a substantial AI subsystem.

## How to read these docs

| Doc | Purpose |
|-----|---------|
| [SYSTEM_DESIGN_SUMMARY.md](SYSTEM_DESIGN_SUMMARY.md) | **Start here** — one-page map + links |
| [C4_CONTEXT.md](C4_CONTEXT.md) | **Level 1** — system context (actors + externals) |
| [C4_CONTAINER.md](C4_CONTAINER.md) | **Level 2** — logical containers inside the monolith |
| [C4_COMPONENTS.md](C4_COMPONENTS.md) | **Level 3** — major components and responsibilities |
| [SEQUENCES_PAYMENT_FLOW.md](SEQUENCES_PAYMENT_FLOW.md) | Payment paths: authorize, capture, refund, void |
| [SEQUENCES_AI_FLOW.md](SEQUENCES_AI_FLOW.md) | AI paths: dashboard orchestration vs agent+RAG |
| [SEQUENCES_WEBHOOK_FLOW.md](SEQUENCES_WEBHOOK_FLOW.md) | Inbound processor webhooks + outbound merchant delivery |

## Related existing docs

- [ARCHITECTURE.md](ARCHITECTURE.md) — directory-oriented overview (older; still useful)
- [SEQUENCE_DIAGRAMS.md](SEQUENCE_DIAGRAMS.md) — Mermaid diagrams (payment-focused)
- [SYSTEM_DESIGN_AND_ARCHITECTURE.md](SYSTEM_DESIGN_AND_ARCHITECTURE.md) — narrative system design
- [AI_PLATFORM.md](AI_PLATFORM.md), [AI_REQUEST_FLOW.md](AI_REQUEST_FLOW.md), [AI_CI_QUALITY_GATES.md](AI_CI_QUALITY_GATES.md)
- [PAYMENT_PROVIDER_SANDBOX.md](PAYMENT_PROVIDER_SANDBOX.md), [PROVIDER_ADAPTER_ARCHITECTURE.md](PROVIDER_ADAPTER_ARCHITECTURE.md)

## Principles (accurate to code)

- **Multi-tenant:** all tenant data scoped by `merchant_id` / `current_merchant`.
- **Monolith:** one deployable app; “containers” in C4 are **logical** boundaries, not separate processes (except DB/cache and external HTTP).
- **Optional behavior** is **flag/env gated** (AI graph/vector retrieval, streaming, provider mode). See each doc for caveats.
