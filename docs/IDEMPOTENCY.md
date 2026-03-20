# Idempotency

Mutating payment API operations accept an optional `idempotency_key`. The gateway stores the first successful outcome per **(merchant, idempotency_key, endpoint)** and replays it only when the **logical request** matches the original.

## Protected endpoints

| Endpoint | HTTP | `endpoint` value in `IdempotencyRecord` |
|----------|------|----------------------------------------|
| Create payment intent | `POST /api/v1/payment_intents` | `create_payment_intent` |
| Authorize | `POST /api/v1/payment_intents/:id/authorize` | `authorize` |
| Capture | `POST /api/v1/payment_intents/:id/capture` | `capture` |
| Void | `POST /api/v1/payment_intents/:id/void` | `void` |
| Refund | `POST /api/v1/payment_intents/:payment_intent_id/refunds` | `refund` |

The dashboard uses the same `IdempotencyService` for authorize, capture, void, and refund (generated or submitted idempotency keys).

## Scoping

- **Tenant:** Rows are unique on `(merchant_id, idempotency_key, endpoint)`. The same key string on another merchant is unrelated.
- **Endpoint:** The same key may be used for `authorize` and later for `capture` on the same payment intent; those are separate idempotency scopes.

## Request fingerprint (v1)

`IdempotencyRecord.request_hash` stores **SHA256** of a canonical JSON envelope:

- `v` — schema version (`1`).
- `merchant_id` — explicit tenant binding in the hash.
- `endpoint` — action name (e.g. `authorize`).
- `payload` — normalized logical fields for that endpoint (see `IdempotencyFingerprint`).

`idempotency_key` is **not** part of the payload (it already scopes the row).

### Per-endpoint payload

- **`create_payment_intent`:** `customer_id`, `payment_method_id`, `amount_cents` (integer), `currency` (uppercased), `metadata` (deep key-sorted object). Missing optional fields are normalized consistently.
- **`authorize` / `capture` / `void`:** `payment_intent_id`.
- **`refund`:** `payment_intent_id`, `amount_cents` (the effective refund amount after defaults).

Unknown endpoints use a deep key–sorted copy of permitted params (excluding `idempotency_key`).

### Legacy rows

Records created before fingerprint v1 used `SHA256(request_params.to_json)`. Replays still match if that legacy hash equals the incoming legacy computation, so old cached responses remain valid for identical replays.

## Replay behavior

- **Same key + same fingerprint:** Return the stored JSON body and HTTP status. The mutation is **not** run again (no duplicate transactions, ledger lines, webhooks, or audits from the domain service).
- **Same key + different fingerprint:** **409 Conflict** with `error.code` = `idempotency_conflict` and a generic message. The previous response is **not** returned.

## Mismatch observability

On fingerprint mismatch the app:

- Emits a structured **warn** log (`event: idempotency_mismatch`) with `merchant_id`, `endpoint`, `idempotency_key`, `mismatch_detected`, `request_hash_mismatch`, and `request_id` (no raw card or full request body).
- Writes an **`AuditLog`** with `action: idempotency_mismatch` and the same safe metadata.

## Client guidance

- Use a unique idempotency key per logical operation; retry the **same** key only when retrying the **same** request (network timeout, etc.).
- After a **409** for `idempotency_conflict`, generate a **new** key if you intend a different amount, payment intent, or refund size.
