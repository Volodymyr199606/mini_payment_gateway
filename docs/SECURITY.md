# Mini Payment Gateway – Security

---

## 1. Authentication

| Surface | Mechanism |
|---------|-----------|
| **API** | `X-API-KEY` header. `Merchant.find_by_api_key(key)` via `ApiAuthenticatable`. |
| **Dashboard** | Session (`session[:merchant_id]`). Sign-in via email/password or API key. |

**API key storage:** bcrypt digest only. Plain key shown once at creation/regeneration.

---

## 2. Authorization (Merchant Scoping)

All data access is scoped to `current_merchant`:

- `current_merchant.payment_intents.find(id)`
- `current_merchant.customers`
- `current_merchant.customers` when resolving payment methods

**Assumption:** No cross-merchant access. RecordNotFound is raised if ID does not belong to current merchant.

---

## 3. Payment Method / PCI

- **No raw card data:** Only token, last4, brand, exp_month, exp_year stored.
- **Token generation:** `pm_#{SecureRandom.hex(16)}` (model) or `pm_demo_#{SecureRandom.hex(8)}` (dashboard).
- **Assumption:** Card collection and tokenization happen off-platform (e.g. future client SDK or processor). This app never handles PAN.

See `docs/PCI_COMPLIANCE.md` for existing PCI notes.

---

## 4. Webhook Signature

- **Algorithm:** HMAC-SHA256 (via `WebhookSignatureService`).
- **Secret:** `Rails.application.config.webhook_secret` (env: `WEBHOOK_SECRET`).
- **Header:** `X-WEBHOOK-SIGNATURE` on outbound webhooks.

**Inbound webhooks** (`POST /api/v1/webhooks/processor`): Signature verification is implemented for processor events.

---

## 5. Rate Limiting

- `RateLimiterService` and `ApiRequestStat` track requests per merchant per day.
- 429 returned when limit exceeded.
- Counters: `requests_count`, `errors_count`, `rate_limited_count`.

---

## 6. Audit Trail

- `AuditLogService` and `Auditable` concern.
- Actions: `payment_authorized`, `payment_authorization_failed`, `payment_captured`, `payment_voided`, `payment_refunded`, etc.
- Stored: `actor_type`, `actor_id`, `action`, `auditable_type`, `auditable_id`, `metadata`.

---

## 7. Logging

- `StructuredLogging` concern and `SafeLogHelper` for sanitized logs.
- `RequestIdMiddleware` adds `request_id` to logs.
- Token/keys redacted (e.g. `token=[REDACTED]`).

---

## 8. Secrets

| Secret | Source | Use |
|--------|--------|-----|
| `api_key` | Generated, shown once | Auth for API |
| `password_digest` | bcrypt of password | Dashboard sign-in |
| `webhook_secret` | `WEBHOOK_SECRET` env | Webhook HMAC |
| `MERCHANT_WEBHOOK_URL` | Env | Outbound webhook URL (assumption: per-merchant in future) |
