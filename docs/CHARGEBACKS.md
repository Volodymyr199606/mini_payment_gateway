# Chargebacks in Mini Payment Gateway

This document describes how chargebacks are handled in the mini payment gateway.

## What is a Chargeback?

A **chargeback** is when a cardholder disputes a charge with their bank. The bank reverses the transaction, and the merchant may lose the funds. Chargebacks are a consumer-protection mechanism and can result from fraud, unrecognized charges, or product disputes.

## How We Simulate It

Chargebacks are ingested **only via webhook event**. The processor (or simulator) sends a `chargeback.opened` event to:

```
POST /api/v1/webhooks/processor
```

With a payload like:

```json
{
  "event_type": "chargeback.opened",
  "data": {
    "merchant_id": 1,
    "payment_intent_id": 123,
    "chargeback_id": "cb_xyz789",
    "amount_cents": 5000,
    "reason_code": "fraud"
  }
}
```

- The event is stored as a `WebhookEvent` (like other processor events).
- If `data.payment_intent_id` is present and belongs to the merchant, we set `payment_intents.dispute_status` to `"open"`.

## What We Track

| Item | Description |
|------|-------------|
| **WebhookEvent** | All chargeback events are stored with `event_type: "chargeback.opened"`. |
| **dispute_status** | Optional field on `PaymentIntent`: `"none"` (default) or `"open"`. |
| **Dashboard** | Webhook list shows a "Chargeback" badge for chargeback events. Payment Intent show page displays dispute status. |

## What We Intentionally Do NOT Implement

- **No full dispute system** – no dispute lifecycle (opened → won/lost → closed).
- **No dispute transitions** – only `none` → `open`; no `won`, `lost`, `closed`, etc.
- **No chargeback API** – you cannot create or resolve chargebacks via our API; they arrive only as webhooks.
- **No ledger entries** – we do not automatically create ledger entries for chargebacks.
- **No reversal of capture** – chargebacks do not change `PaymentIntent` status (e.g. `captured` stays `captured`).

This is a minimal, webhook-only implementation for learning and simulation.
