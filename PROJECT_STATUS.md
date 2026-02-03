# Mini Payment Gateway — What Is Done Already

A Rails 7+ API and dashboard that models a Braintree-style payment platform. Below is what is implemented.

---

## 1. Foundation & Config

- **Rails 7.2** (API + views), **PostgreSQL**, **Ruby ≥ 3.1**
- **Auth:** API key auth via `X-API-KEY`; dashboard sign-in with API key (session-based)
- **Config:** CORS (`rack-cors`), dotenv for DB credentials, tzinfo-data for Windows, importmap + Turbo + Stimulus
- **Middleware:** `RequestIdMiddleware` — generates/forwards `X-Request-ID`, sets thread-local for logging
- **Windows:** Puma single-worker mode, README PATH note, migrations with `if_not_exists` / no duplicate indexes

---

## 2. Data Layer

### Models & Associations

| Model | Purpose |
|-------|--------|
| **Merchant** | API key (BCrypt digest), status (active/inactive), `create_with_api_key`, `find_by_api_key` |
| **Customer** | Belongs to merchant; email, name; scoped per merchant |
| **PaymentMethod** | Belongs to customer; method_type, last4, brand, exp, token (unique) |
| **PaymentIntent** | Merchant, customer, optional payment_method; amount_cents, currency, status (created → authorized → captured / canceled / failed); idempotency_key, metadata |
| **Transaction** | Belongs to payment_intent; kind (authorize, capture, void, refund), status, amount_cents, processor_ref, failure_* |
| **LedgerEntry** | Merchant, optional transaction; entry_type, amount_cents, currency |
| **WebhookEvent** | Optional merchant; event_type, payload, signature, delivery_status, attempts, delivered_at |
| **AuditLog** | Optional merchant; actor_type/id, action, auditable_type/id, metadata |
| **IdempotencyRecord** | Merchant; idempotency_key, endpoint, request_hash, response_body, status_code; unique on (merchant_id, idempotency_key, endpoint) |

### Migrations & Schema

- 9 migrations: merchants, customers, payment_methods, payment_intents, transactions, ledger_entries, webhook_events, audit_logs, idempotency_records
- Indexes and FKs in place; schema is up to date

### Seeds

- 2 merchants with API keys (printed to console)
- Customers, payment methods, payment intents, transactions, ledger entries, sample webhook events

---

## 3. API (`/api/v1`)

- **Base:** `Api::V1::BaseController` — includes `ApiAuthenticatable`, global rescue for `StandardError`, `RecordInvalid`, `ParameterMissing`; structured error JSON
- **Auth:** `ApiAuthenticatable` — `current_merchant` from `X-API-KEY`; 401 when missing/invalid
- **Pagination:** `Paginatable` concern + Kaminari (default page size)
- **Structured logging:** request_id, merchant_id, transaction_id where relevant

### Endpoints

| Method | Path | Auth | Purpose |
|--------|------|------|--------|
| GET | `/api/v1/health` | No | `{ status: "ok" }` |
| POST | `/api/v1/merchants` | No | Create merchant; returns API key |
| GET | `/api/v1/merchants/me` | Yes | Current merchant |
| GET/POST | `/api/v1/customers` | Yes | List (paginated) / create |
| GET | `/api/v1/customers/:id` | Yes | Show customer |
| POST | `/api/v1/customers/:customer_id/payment_methods` | Yes | Create payment method |
| GET/POST | `/api/v1/payment_intents` | Yes | List (paginated) / create |
| GET | `/api/v1/payment_intents/:id` | Yes | Show payment intent |
| POST | `/api/v1/payment_intents/:id/authorize` | Yes | Authorize |
| POST | `/api/v1/payment_intents/:id/capture` | Yes | Capture |
| POST | `/api/v1/payment_intents/:id/void` | Yes | Void |
| POST | `/api/v1/payment_intents/:id/refunds` | Yes | Create refund |
| POST | `/api/v1/webhooks/processor` | No (signature) | Ingest processor events |

---

## 4. Payment Flow (Service Objects)

- **BaseService:** `call`, `success?` / `failure?`, `result`, `errors`, `add_error`, `set_result`
- **IdempotencyService:** Per (merchant, idempotency_key, endpoint); caches response for duplicate requests
- **AuthorizeService:** Creates authorize transaction, simulates processor, updates payment intent to authorized/failed; ledger + webhook + audit
- **CaptureService:** From authorized → captured; capture transaction, ledger, webhook, audit
- **VoidService:** From authorized → canceled; void transaction, ledger, webhook, audit
- **RefundService:** Partial/full refund from captured; refund transaction, ledger, webhook, audit
- **LedgerService:** Writes `LedgerEntry` for charges, refunds, fees
- **AuditLogService / Auditable:** Logs payment actions (e.g. authorize, capture, void, refund)
- **WebhookTriggerable:** Enqueues webhook events on success/failure

State rules (e.g. authorize only from created, capture only from authorized) are enforced in the services.

---

## 5. Webhooks

- **WebhookSignatureService:** HMAC-SHA256 verification for incoming processor webhooks
- **ProcessorEventService:** Simulates processor events; creates `WebhookEvent` and enqueues delivery
- **WebhookDeliveryService / WebhookDeliveryJob:** Async delivery with retries (exponential backoff)
- **POST /api/v1/webhooks/processor:** Receives simulated events; signature verified, then processed and delivered asynchronously

---

## 6. Observability & Safety

- **Rate limiting:** Per-merchant (e.g. 100 req/60s); `X-RateLimit-*` headers
- **Structured logging:** JSON-style logs with request_id, merchant_id, transaction_id
- **Audit logs:** AuditLog records for important payment actions
- **Request ID:** End-to-end via middleware and response header

---

## 7. Dashboard (HTML)

- **Auth:** Session sign-in with API key; `Dashboard::BaseController` + `authenticate_merchant!`; `current_merchant` exposed as helper
- **Routes:** `/dashboard` (root → sign-in or redirect), `/dashboard/sign_in`, `/dashboard/transactions`, `/dashboard/payment_intents/:id`, `/dashboard/ledger`
- **Controllers:** `Dashboard::SessionsController`, `TransactionsController`, `PaymentIntentsController`, `LedgerController`
- **Views:** Sign-in, transactions list (filters, pagination), payment intent show, ledger summary; layout with nav (Transactions, Ledger, merchant name, Sign Out)
- **Assets:** application.css, importmap + Turbo + Stimulus

---

## 8. Summary Checklist

| Area | Done |
|------|------|
| Rails + Postgres + API skeleton | ✅ |
| API key auth (API + dashboard) | ✅ |
| Models, migrations, validations, seeds | ✅ |
| API CRUD + payment actions (authorize/capture/void/refund) | ✅ |
| Idempotency | ✅ |
| Ledger entries | ✅ |
| Webhooks (receive, verify, async delivery, retries) | ✅ |
| Logging, request ID, rate limit, audit log | ✅ |
| Dashboard (sign-in, transactions, payment intent, ledger) | ✅ |
| Windows-friendly setup (Puma, PATH, migrations, tzinfo-data) | ✅ |

---

*Last updated from codebase review. For API usage and setup steps, see README.md.*
