# Mini Payment Gateway – Documentation Index

| Document | Purpose |
|----------|---------|
| [SYSTEM_DESIGN_SUMMARY.md](SYSTEM_DESIGN_SUMMARY.md) | **Portfolio / interview entry** — one-page map + links to C4 + sequences |
| [ARCHITECTURE_OVERVIEW.md](ARCHITECTURE_OVERVIEW.md) | Index for C4-style package + related architecture docs |
| [C4_CONTEXT.md](C4_CONTEXT.md) | C4 Level 1 — system context (actors, externals) |
| [C4_CONTAINER.md](C4_CONTAINER.md) | C4 Level 2 — logical containers in the monolith |
| [C4_COMPONENTS.md](C4_COMPONENTS.md) | C4 Level 3 — major components, responsibilities, trade-offs |
| [SEQUENCES_PAYMENT_FLOW.md](SEQUENCES_PAYMENT_FLOW.md) | Step-by-step authorize, capture, refund, void (+ Mermaid) |
| [SEQUENCES_AI_FLOW.md](SEQUENCES_AI_FLOW.md) | Dashboard orchestration vs agent+RAG; API AI summary |
| [SEQUENCES_WEBHOOK_FLOW.md](SEQUENCES_WEBHOOK_FLOW.md) | Inbound processor webhooks vs outbound merchant delivery |
| [ARCHITECTURE.md](ARCHITECTURE.md) | System overview, directory structure, service usage, implementation plan |
| [PAYMENT_LIFECYCLE.md](PAYMENT_LIFECYCLE.md) | Authorize vs capture, statuses, void/refund, timeouts, ledger implications |
| [SEQUENCE_DIAGRAMS.md](SEQUENCE_DIAGRAMS.md) | Mermaid sequence diagrams (authorize, capture, refund, webhook, idempotency) |
| [DATA_FLOW.md](DATA_FLOW.md) | Payment lifecycle data, ledger conventions, entity relationships |
| [SECURITY.md](SECURITY.md) | Auth, merchant scoping, PCI, webhooks, rate limiting |
| [DEPLOYMENT.md](DEPLOYMENT.md) | Environment variables, jobs, production checklist |
| [DIAGRAMS.md](DIAGRAMS.md) | System context, containers, state machine, ERD |

**Additional docs:**
- [AI_AGENTS.md](AI_AGENTS.md) – AI chat endpoint, agents, RAG, env vars, safety
- [REFUNDS_API.md](REFUNDS_API.md) – Refunds API details
- [METRICS.md](METRICS.md) – Metrics and observability
- [PCI_COMPLIANCE.md](PCI_COMPLIANCE.md) – PCI compliance notes
- [CHARGEBACKS.md](CHARGEBACKS.md) – Chargeback handling
- [TIMEOUTS.md](TIMEOUTS.md) – Timeout configuration
- [SYSTEM_DESIGN_AND_ARCHITECTURE.md](SYSTEM_DESIGN_AND_ARCHITECTURE.md) – Narrative system design / architecture
- [PROVIDER_ADAPTER_ARCHITECTURE.md](PROVIDER_ADAPTER_ARCHITECTURE.md) – Payment provider adapter layer
- [PAYMENT_PROVIDER_SANDBOX.md](PAYMENT_PROVIDER_SANDBOX.md) – Stripe sandbox / `PAYMENTS_PROVIDER` configuration
