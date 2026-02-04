# Refunds API

## Endpoint

**POST** `/api/v1/payment_intents/:payment_intent_id/refunds`

- **Auth:** `X-API-KEY` header (required).
- **Rules:** Only payment intents in `captured` status can be refunded. Partial refunds via `refund.amount_cents`; omit for full refund. Total refunds cannot exceed captured amount. Idempotency key prevents duplicate refund transactions/ledger entries for the same (merchant, endpoint, idempotency_key).

---

## Example request (partial refund)

```http
POST /api/v1/payment_intents/1/refunds
Content-Type: application/json
X-API-KEY: your_api_key_here

{
  "refund": { "amount_cents": 5000 },
  "idempotency_key": "refund-partial-001"
}
```

## Example request (full refund)

Omit `amount_cents` to refund remaining `refundable_cents`:

```http
POST /api/v1/payment_intents/1/refunds
Content-Type: application/json
X-API-KEY: your_api_key_here

{
  "idempotency_key": "refund-full-001"
}
```

---

## Example response (201 Created)

```json
{
  "data": {
    "transaction": {
      "id": 42,
      "payment_intent_id": 1,
      "kind": "refund",
      "status": "succeeded",
      "amount_cents": 5000,
      "processor_ref": "txn_abc123...",
      "failure_code": null,
      "failure_message": null,
      "created_at": "2026-01-27T12:00:00.000Z",
      "updated_at": "2026-01-27T12:00:00.000Z"
    },
    "payment_intent": {
      "id": 1,
      "merchant_id": 1,
      "customer_id": 1,
      "payment_method_id": 1,
      "amount_cents": 10000,
      "amount": 100.0,
      "currency": "USD",
      "status": "captured",
      "refundable_cents": 5000,
      "total_refunded_cents": 5000,
      "created_at": "...",
      "updated_at": "..."
    },
    "refund_amount_cents": 5000
  }
}
```

## Example error (422 – invalid state)

```json
{
  "error": {
    "code": "invalid_state",
    "message": "Payment intent must be in 'captured' state to refund",
    "details": {}
  }
}
```

## Example error (422 – amount exceeds refundable)

```json
{
  "error": {
    "code": "validation_error",
    "message": "Refund amount exceeds refundable amount",
    "details": {
      "refundable_cents": 5000,
      "requested_cents": 7000
    }
  }
}
```

## Example error (422 – refund failed, e.g. processor simulation)

```json
{
  "error": {
    "code": "refund_failed",
    "message": "Refund failed",
    "details": {}
  }
}
```

---

## DB / SQL verification queries

**Refund transactions for a payment intent:**

```sql
SELECT id, payment_intent_id, kind, status, amount_cents, processor_ref, created_at
FROM transactions
WHERE payment_intent_id = :payment_intent_id
  AND kind = 'refund'
ORDER BY created_at;
```

**Ledger entries for refunds (negative amount_cents):**

```sql
SELECT le.id, le.entry_type, le.amount_cents, le.currency, le.transaction_id, t.kind AS txn_kind, t.amount_cents AS txn_amount
FROM ledger_entries le
JOIN transactions t ON t.id = le.transaction_id
WHERE le.merchant_id = :merchant_id
  AND le.entry_type = 'refund'
ORDER BY le.created_at;
```

**Idempotency: one row per (merchant, idempotency_key, endpoint) for refunds:**

```sql
SELECT idempotency_key, endpoint, status_code, request_hash, created_at, updated_at
FROM idempotency_records
WHERE merchant_id = :merchant_id
  AND endpoint = 'refund'
ORDER BY created_at;
```

**Sanity: refundable vs total refunded (derived from transactions):**

```sql
SELECT
  pi.id AS payment_intent_id,
  pi.status,
  pi.amount_cents AS intent_amount,
  (SELECT COALESCE(SUM(t.amount_cents), 0) FROM transactions t WHERE t.payment_intent_id = pi.id AND t.kind = 'capture' AND t.status = 'succeeded') AS captured_cents,
  (SELECT COALESCE(SUM(t.amount_cents), 0) FROM transactions t WHERE t.payment_intent_id = pi.id AND t.kind = 'refund' AND t.status = 'succeeded') AS total_refunded_cents
FROM payment_intents pi
WHERE pi.id = :payment_intent_id;
```
