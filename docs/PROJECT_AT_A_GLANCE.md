# Project at a glance

One-page **architecture summary** for interviews and portfolio—faster than reading all C4 diagrams. For depth, follow links.

---

## One-sentence design

A **Rails monolith** exposes a merchant-scoped payment API and dashboard, routes processor calls through **adapter-selected** providers (simulated or Stripe), persists **transactions + ledger** with **idempotency**, and layers an **optional AI stack** (tools + RAG + policy) on the same domain models.

---

## Major components

```
┌─────────────────────────────────────────────────────────────────┐
│  Clients: API (X-API-KEY) · Dashboard (session) · Processor webhooks │
└───────────────────────────────┬─────────────────────────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        ▼                       ▼                       ▼
┌───────────────┐     ┌─────────────────┐     ┌──────────────────┐
│ API controllers│     │ Dashboard       │     │ WebhooksController│
│ (idempotency) │     │ (Hotwire)       │     │ (verify + normalize)│
└───────┬───────┘     └────────┬────────┘     └─────────┬────────┘
        │                      │                        │
        └──────────────────────┼────────────────────────┘
                               ▼
                    ┌──────────────────────┐
                    │ Services (authorize, │
                    │ capture, void, refund)│
                    └──────────┬───────────┘
                               │
        ┌──────────────────────┼──────────────────────┐
        ▼                      ▼                      ▼
┌───────────────┐    ┌─────────────────┐    ┌──────────────────┐
│ ProviderRegistry│   │ Ledger, Audit, │    │ WebhookEvent +   │
│ → Simulated /   │   │ Idempotency    │    │ delivery job     │
│   StripeAdapter │   │                │    │                  │
└───────────────────┘   └─────────────────┘   └──────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ AI (optional): orchestration → tools / retrieval → LLM (Groq)    │
│ Policy · AiRequestAudit · replay · analytics / health (dev)       │
└─────────────────────────────────────────────────────────────────┘
```

---

## Key request flows (short)

| Flow | Path |
|------|------|
| **Authorize** | Validate `created` → adapter `authorize` → `Transaction` → intent `authorized` or `failed` |
| **Capture** | Validate `authorized` → adapter `capture` → charge **ledger** entry → `captured` |
| **Refund** | Validate `captured` → adapter `refund` → negative **ledger** entry |
| **Void** | `created`/`authorized` → adapter `void` → `canceled`; no ledger charge |
| **Inbound webhook** | Verify signature → normalize → optional dedupe by `provider_event_id` → `WebhookEvent` → outbound job |
| **AI chat** | Plan → policy → tools and/or RAG → compose response → audit |

---

## Simulated vs real

| Piece | Default | Optional real |
|-------|---------|----------------|
| Payment processor | Simulated (random-ish outcomes) | `stripe_sandbox` + Stripe test keys |
| LLM | Stubbed in tests | Groq when `GROQ_API_KEY` set |
| Webhooks (inbound) | HMAC with app secret | Stripe `Stripe-Signature` when using Stripe |

---

## How AI fits the payment platform

- **Same database:** Tools read `PaymentIntent`, `Transaction`, `LedgerEntry`, `WebhookEvent` scoped to merchant.
- **Deterministic path:** Structured tools return JSON for audits and tests.
- **LLM path:** Explains policies, lifecycle, and docs; RAG pulls from `docs/` chunks.
- **Guardrails:** Policy, adversarial specs, contract tests—no substitute for domain isolation.

---

## Important trade-offs (compressed)

- **Monolith:** simpler consistency; not optimizing for independent service deploys.
- **Adapter:** keeps Stripe details out of services; swap providers without rewriting domain.
- **AI:** powerful for demos; adds moving parts—CI is split to catch regressions early.

---

## Deeper reading

| Topic | Doc |
|-------|-----|
| C4 + sequences | [SYSTEM_DESIGN_SUMMARY.md](SYSTEM_DESIGN_SUMMARY.md) |
| Payment lifecycle | [PAYMENT_LIFECYCLE.md](PAYMENT_LIFECYCLE.md) |
| Provider adapters | [PROVIDER_ADAPTER_ARCHITECTURE.md](PROVIDER_ADAPTER_ARCHITECTURE.md) |
| AI platform | [AI_PLATFORM.md](AI_PLATFORM.md) |
