# Demo Script and AI Demo Flows

This document provides a repeatable demo script for the payment gateway: core product flow, dashboard, AI tools, hybrid docs+tool answers, follow-ups, and internal tooling. Use it for portfolio walkthroughs and internal validation.

**Prerequisites:** Run demo seed once so IDs and data exist:

```bash
bundle exec rails demo:seed
# or: bin/setup_demo
```

After seeding, use the printed **demo merchant** email/password and the **Notable IDs** (payment intent IDs, transaction IDs, webhook IDs) in the steps below. Credentials and IDs are also written to `tmp/demo_summary.txt` in development.

---

## 1. One-command demo setup

```bash
bin/setup_demo
# or
bundle exec rails demo:seed
```

This resets and seeds demo data (development only), then prints:

- Demo merchant login (email / password) and API key  
- Notable payment intent, transaction, and webhook IDs  
- Scoping merchant login (for multi-tenant demos)  
- Suggested prompts  

Use the printed IDs in the prompts below (e.g. replace `PAYMENT_INTENT_ID` with the actual ID for the authorized intent).

---

## 2. Payment gateway core product flow

**Goal:** Show create → authorize → capture → refund and ledger.

1. **Create payment intent** (API or dashboard): Create a payment intent for the demo merchant (e.g. amount 5000 cents, customer and payment method from seed).
2. **Authorize:** Call authorize endpoint; show intent moving to `authorized` and transaction `kind: authorize`, `status: succeeded`.
3. **Capture:** Call capture endpoint; show intent `captured`, new transaction `kind: capture`, and a **ledger charge** entry.
4. **Refund:** Call refund endpoint (full or partial); show refund transaction and **ledger refund** entry.
5. **Reporting:** Use ledger summary (API or AI tool) for “last 7 days” to show charges and refunds.

Seeded data already includes intents in `created`, `authorized`, `captured`, refunded, `failed`, and `canceled`, so you can also walk through “why is this intent still authorized?” and “show a failed payment” without creating new data.

---

## 3. Dashboard walkthrough

1. **Sign in:** Use demo merchant email and password from the seed output (e.g. `demo@example.com` / `demo1234`).
2. **Transactions:** Open the transactions list; show multiple kinds (authorize, capture, refund, void) and statuses (succeeded, failed).
3. **Payment intents:** Show intents in different statuses (created, authorized, captured, refunded, failed, canceled).
4. **Ledger / reporting:** Show ledger or reporting view with charges and refunds over time.
5. **Webhooks:** Show webhook events with mixed delivery states (pending, succeeded, failed).

---

## 4. AI deterministic tool demos

Use the **AI chat** (dashboard or API) with the demo merchant’s API key. Substitute the printed IDs from the seed output.

| Goal | Example prompt |
|------|-----------------|
| Payment intent lookup | “What is the status of payment intent **PAYMENT_INTENT_ID**?” (use the authorized intent ID for “requires_capture” story) |
| Transaction lookup | “Show me transaction **TRANSACTION_ID**.” (use the printed capture or refund transaction ID) |
| Ledger summary | “What is my net volume for the last 7 days?” |
| Ledger preset | “Give me the ledger summary for yesterday.” |
| Webhook status | “What happened to webhook **WEBHOOK_ID**?” (use succeeded, failed, or pending webhook ID) |

These should hit the deterministic tools (`get_payment_intent`, `get_transaction`, `get_ledger_summary`, `get_webhook_event`) and return structured data.

---

## 5. AI hybrid docs + tool demos

Combine tool results with RAG/docs so the model can explain concepts using both live data and documentation.

| Goal | Example prompt |
|------|-----------------|
| Explain payment intent state with docs | “What does **requires_capture** mean?” then “What is the status of payment intent **AUTHORIZED_INTENT_ID**?” — show explanation plus current intent state. |
| Explain refunds with ledger + docs | “Explain how refunds affect my ledger.” Then ask for “ledger summary for the last 7 days” or “last month” to show charges and refunds. |
| Auth vs capture | “What’s the difference between authorize and capture?” (docs) then show an authorized intent and a captured intent from seeded data. |

---

## 6. Follow-up demos

Demonstrate follow-up inheritance and context (e.g. “what about yesterday?”, “only failed ones”).

| Goal | Example prompt (after a prior question) |
|------|----------------------------------------|
| Time shift | First: “What is my net volume for the last 7 days?” Then: “What about **yesterday**?” |
| Simpler explanation | After any technical answer: “Explain that more simply.” |
| Follow-up on intent | After looking up a payment intent: “Was it captured after that?” or “What’s the status now?” |
| Filter | “Show me **failed** captures this week.” (relies on seeded failed intent/captures) |

Use the seeded timeline (intents and ledger entries spread over the last 7 days and “yesterday”) so “yesterday” and “last 7 days” return meaningful data.

---

## 7. Internal tooling demos

**AI analytics:** Open the AI analytics page (e.g. `/dashboard/ai/analytics` or equivalent). Show request volume, success rate, tool usage, and any breakdown by agent or endpoint. Seeded AI request audits should appear.

**AI health:** Open the AI health page. Show health status and any metrics (latency, errors, fallbacks). Confirm the system is healthy with the seeded data.

**AI audit drill-down:** From the audit list, open a request that used a tool (e.g. `get_payment_intent` or `get_ledger_summary`). Show that the audit record has no raw prompts/secrets but does show tool used, success, and high-level metadata.

**Replayable request debugging:** Use the replay/debug tool to replay a request by ID or by parameters (e.g. payment_intent_id). Show that the same tool is invoked and the result is deterministic. Use a seeded payment intent ID or transaction ID.

---

## 8. Preset example prompts (curated)

Use these with the **demo merchant** and the IDs printed after `rails demo:seed`. Replace placeholders with actual IDs from `tmp/demo_summary.txt` or the console output.

- “What is the status of payment intent **AUTHORIZED_PI_ID**?”  
- “Why did payment intent **FAILED_PI_ID** fail?”  
- “What is my net volume for the last 7 days?”  
- “What happened to webhook **WEBHOOK_ID**?”  
- “What does **requires_capture** mean?”  
- “Show me failed captures this week.”  
- “Explain that more simply.” (as follow-up)  
- “What about yesterday?” (as follow-up after a time-range question)  
- “Give me the ledger summary for yesterday.”  
- “Show me transaction **TRANSACTION_ID**.”

---

## 9. Multi-tenant / scoping demos

Use the **scoping merchant** (separate email/password from seed output) to show:

- **Merchant scoping:** Sign in or use the scoping merchant’s API key; show that only that merchant’s payment intents, transactions, and webhooks are visible.
- **Policy enforcement:** With the scoping merchant, ask for a **demo merchant** payment intent ID by number — the AI/API should deny or return “not found” (no cross-tenant leakage).
- **Adversarial / blocked access:** From the scoping merchant, try to access the demo merchant’s resource by ID; confirm blocked or empty result.

Keep the scoping merchant’s data minimal so the focus is on isolation, not volume.

---

## 10. Quick reference: what the seed provides

| Concept | Purpose |
|--------|----------|
| Demo merchant | Rich history: multiple customers, payment methods, intents in created/authorized/captured/refunded/failed/canceled, transactions, ledger entries, webhooks (pending/succeeded/failed), AI audit rows. |
| Timeline | Created_at spread over last 7 days and “today” so “last 7 days”, “yesterday”, “this week” and “today” return meaningful reporting/AI answers. |
| Authorized intent | Explains “requires_capture” and “why is this still authorized?” |
| Failed intent | “Why did this fail?” and “failed captures this week.” |
| Refund + ledger | Partial refund and ledger charge/refund entries for docs+tool hybrid. |
| Webhook mix | Pending, succeeded, failed for webhook status and “what happened to webhook X?” |
| Scoping merchant | Second tenant with its own data for policy and multi-tenant demos. |

After running the demo seed, the script references above and the preset prompts align with this data for a repeatable, portfolio-ready demo.
