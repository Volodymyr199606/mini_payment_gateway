# Mini Payment Gateway – Data Flow

How data moves through the system for payments, ledger, webhooks, and idempotency.

---

## 1. Payment Intent Lifecycle (Data)

```
PaymentIntent (status: created)
    │
    ├── AuthorizeService
    │       └── Transaction (kind: authorize, status: succeeded/failed)
    │       └── PaymentIntent.status = authorized | failed
    │
    ├── [if authorized] CaptureService
    │       └── Transaction (kind: capture, status: succeeded/failed)
    │       └── PaymentIntent.status = captured | failed
    │       └── LedgerEntry (entry_type: charge, amount_cents: +)
    │
    ├── [if authorized] VoidService
    │       └── Transaction (kind: void, status: succeeded/failed)
    │       └── PaymentIntent.status = canceled
    │
    └── [if captured] RefundService
            └── Transaction (kind: refund, status: succeeded/failed)
            └── LedgerEntry (entry_type: refund, amount_cents: -)
            └── PaymentIntent.status = captured (unchanged)
```

---

## 2. Ledger Sign Convention

| Entry Type | Amount Sign | When Created |
|------------|-------------|--------------|
| `charge` | Positive | Capture succeeds (`CaptureService`) |
| `refund` | Negative | Refund succeeds (`RefundService`) |
| `fee` | Positive or negative | (Future: fee adjustments) |

**Assumption:** Net merchant balance = sum of `ledger_entries.amount_cents` for that merchant.

---

## 3. Entity Relationships (Data Flow)

```
Merchant
  ├── Customer (has many)
  │     └── PaymentMethod (has many)
  ├── PaymentIntent (has many)
  │     ├── belongs_to :customer
  │     ├── belongs_to :payment_method (optional)
  │     └── Transaction (has many)
  │           └── LedgerEntry (has one, optional)
  ├── LedgerEntry (has many, via merchant_id)
  ├── IdempotencyRecord (has many)
  ├── WebhookEvent (has many)
  ├── AuditLog (has many)
  └── ApiRequestStat (has many)
```

---

## 4. Idempotency Data Flow

| Step | Action |
|------|--------|
| 1 | Controller receives `idempotency_key` (API) or generates UUID (Dashboard) |
| 2 | `IdempotencyService.call(merchant:, idempotency_key:, endpoint:, request_params:)` |
| 3 | Lookup `IdempotencyRecord` by `(merchant_id, idempotency_key, endpoint)` |
| 4a | If found: return `{ cached: true, response_body, status_code }` |
| 4b | If not found: create placeholder `IdempotencyRecord`, return `{ cached: false }` |
| 5 | Controller calls service (AuthorizeService, etc.) |
| 6 | On success: `idempotency.store_response(response_body:, status_code:)` |
| 7 | On failure: no store; next request with same key will create new placeholder |

**Endpoints:** `create_payment_intent`, `authorize`, `capture`, `void`, `refund`

---

## 5. Webhook Payload Flow

```
Service (AuthorizeService, CaptureService, RefundService)
    │
    └── trigger_webhook_event(event_type:, transaction:, payment_intent:)
            │
            └── ProcessorEventService.call(event_type:, payload:)
                    │
                    ├── WebhookEvent.create!(event_type, payload, delivery_status: 'pending')
                    ├── WebhookSignatureService.generate_signature(payload_json, webhook_secret)
                    ├── webhook_event.update!(signature:)
                    └── WebhookEvent#after_commit → WebhookDeliveryJob.perform_later
                            │
                            └── WebhookDeliveryService
                                    │
                                    └── HTTP POST to MERCHANT_WEBHOOK_URL
                                            Headers: X-WEBHOOK-SIGNATURE, X-WEBHOOK-EVENT-TYPE
```

**Event types:** `transaction.succeeded`, `transaction.failed`, `chargeback.opened` (ProcessorEventService.EVENT_TYPES)

---

## 6. Request Paths (API)

| Path | Data In | Data Out |
|------|---------|----------|
| `POST /api/v1/payment_intents` | customer_id, payment_method_id, amount_cents, currency, idempotency_key? | PaymentIntent JSON |
| `POST /api/v1/payment_intents/:id/authorize` | idempotency_key? | Transaction + PaymentIntent JSON |
| `POST /api/v1/payment_intents/:id/capture` | idempotency_key? | Transaction + PaymentIntent JSON |
| `POST /api/v1/payment_intents/:id/void` | idempotency_key? | Transaction + PaymentIntent JSON |
| `POST /api/v1/payment_intents/:id/refunds` | refund[amount_cents]?, idempotency_key? | Transaction + PaymentIntent + refund_amount_cents |

---

## 7. Dashboard vs API: Create Intent

| Source | Customer | Payment Method | Currency |
|--------|----------|----------------|----------|
| API | Required in params | Required in params | From params (default USD) |
| Dashboard | Auto: most recent or create "Default Customer" | Auto: most recent or create (Visa ****4242, pm_demo_xxx) | Fixed "usd" |
