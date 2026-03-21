# Interview demo guide

**Purpose:** Run a confident, time-boxed walkthrough of Mini Payment Gateway. **Detailed steps and prompts** live in [DEMO_SCRIPT.md](DEMO_SCRIPT.md)—this doc adds **timing**, **story beats**, and **priority order**.

**Prerequisites:** `bundle install`, DB migrated, `rails demo:seed` (or `bin/setup_demo`). Save printed credentials and IDs; `tmp/demo_summary.txt` lists them in development.

---

## Setup (before the interview)

1. `bundle exec rails demo:seed` — note **demo merchant** email/password and **API key**.
2. Optional: `GROQ_API_KEY` if you will show live AI (otherwise mention CI stubs).
3. Open `tmp/demo_summary.txt` or console output for **payment intent IDs**, **transaction IDs**, **webhook IDs**.

---

## What to say in 30 seconds

> “This is a Rails payment gateway monolith: multi-tenant API and dashboard, full authorize–capture–void–refund lifecycle with ledger and idempotency, webhooks with signature verification, and an optional AI layer that uses the same merchant-scoped data with tools, RAG over internal docs, policy, and audit/replay. Processor is simulated by default; Stripe test mode is optional.”

---

## 5-minute demo path

**Goal:** Prove it’s not CRUD—show lifecycle + one differentiator.

| Minute | Show | Story |
|--------|------|--------|
| **0–1** | Dashboard login (demo merchant) → **Transactions** list | “Multiple transaction kinds and statuses from seed data.” |
| **1–2** | **Payment intents** — one authorized, one captured | “State machine, not free-form updates.” |
| **2–3** | **Ledger** or overview | “Charges and refunds; ledger reflects capture/refund, not authorize.” |
| **3–4** | One **API** call or **idempotency** mention | “Same idempotency key → same outcome; no double capture.” |
| **4–5** | **Pick one:** AI deterministic prompt **or** webhooks list | “Either assistant reads real merchant data, or we show inbound/outbound webhook flow.” |

**Example AI prompt (if tools enabled):**  
“What is my net volume for the last 7 days?” (hits ledger summary tool.)

---

## 10–15 minute deeper path

Build on the 5-minute path in this order:

1. **Payment API** — Create → authorize → capture → refund (curl or dashboard); point at **ledger entries** after capture/refund.
2. **Idempotency** — Repeat a request with the same key; show identical response / no duplicate side effects.
3. **Webhooks** — Inbound processor events + delivery status; mention signature verification and adapter.
4. **AI — deterministic tools** — Payment intent lookup, transaction lookup, ledger summary, webhook status (use IDs from seed).
5. **AI — docs + RAG** — e.g. “What’s the difference between authorize and capture?” then tie to a seeded intent.
6. **Multi-tenant (if time)** — Scoping merchant: show isolation or policy denial for another merchant’s ID ([DEMO_SCRIPT.md](DEMO_SCRIPT.md) §9).

### If time allows: internal tooling

- **AI analytics** — volume, tool usage, success rate.
- **AI health** — sanity checks for the AI path.
- **Audit drill-down** — one `AiRequestAudit`: tool used, no raw secrets inappropriately exposed.
- **Replay** — replay a request by audit id (deterministic tool path).

---

## Example prompts (curated)

Use IDs from your seed output.

| Intent | Prompt |
|--------|----------|
| Tool + data | “What is the status of payment intent **&lt;ID&gt;**?” |
| Ledger | “What is my net volume for the last 7 days?” |
| Webhook | “What happened to webhook **&lt;ID&gt;**?” |
| Docs + domain | “What does requires_capture mean?” then “Show status of intent **&lt;ID&gt;**.” |
| Follow-up | After a time-range question: “What about yesterday?” |

Full table: [DEMO_SCRIPT.md](DEMO_SCRIPT.md) §4–§8.

---

## Stories to tell by area

| Area | Narrative |
|------|-----------|
| **Ledger** | “We only book money on capture and refund; authorize holds funds, not revenue.” |
| **Idempotency** | “Retries safe retries; fingerprint stores the response.” |
| **Webhooks** | “Inbound verified by provider adapter; we persist and forward to merchants.” |
| **AI** | “Tools hit the same DB as the API; policy blocks cross-tenant access; audits are replayable.” |
| **CI** | “Contract, scenario, and adversarial jobs—so refactors don’t silently break behavior.” |

---

## Honest limitations to mention if asked

- Default processor is **simulated**, not production cards.
- AI is **optional** and needs API keys for live demos.
- **Scale** and **PCI** are modeled seriously in docs but this is a **portfolio / learning** codebase, not a certified processor.

---

## Quick reference

| Need | See |
|------|-----|
| Full demo script | [DEMO_SCRIPT.md](DEMO_SCRIPT.md) |
| Architecture one-pager | [PROJECT_AT_A_GLANCE.md](PROJECT_AT_A_GLANCE.md) |
| Portfolio narrative | [PORTFOLIO_OVERVIEW.md](PORTFOLIO_OVERVIEW.md) |
| Blurbs for resume | [PROJECT_BLURBS.md](PROJECT_BLURBS.md) |
