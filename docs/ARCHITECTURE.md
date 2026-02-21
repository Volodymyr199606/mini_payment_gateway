# Mini Payment Gateway – Architecture

**Version:** 1.0  
**Rails:** 7.2 | **Database:** PostgreSQL  
**Modeled after:** Braintree-style payment lifecycle

---

## 1. System Overview

Mini Payment Gateway is a Rails monolith with two client-facing surfaces:

| Surface | Path | Auth | Protocol |
|---------|------|------|----------|
| **REST API** | `/api/v1/*` | `X-API-KEY` header | JSON |
| **Merchant Dashboard** | `/dashboard/*` | Session (email/password or API key) | HTML (Turbo) |

Both surfaces share the same service layer and data model. Card processing is **simulated** (no real processor integration).

---

## 2. Directory Structure (Actual)

```
app/
├── controllers/
│   ├── api/v1/
│   │   ├── base_controller.rb          # ApiAuthenticatable, StructuredLogging, record_api_request_stat
│   │   ├── health_controller.rb        # GET /health (no auth)
│   │   ├── merchants_controller.rb     # create (disabled), me
│   │   ├── customers_controller.rb     # index, show, create
│   │   ├── payment_methods_controller.rb # create (nested under customers)
│   │   ├── payment_intents_controller.rb # index, show, create, authorize, capture, void
│   │   ├── refunds_controller.rb       # create (nested under payment_intents)
│   │   └── webhooks_controller.rb      # processor (signature verified)
│   ├── dashboard/
│   │   ├── base_controller.rb          # authenticate_merchant!
│   │   ├── sessions_controller.rb      # new, create, destroy
│   │   ├── registrations_controller.rb # new, create
│   │   ├── account_controller.rb       # show, regenerate_api_key, update_credentials
│   │   ├── overview_controller.rb      # index
│   │   ├── transactions_controller.rb  # index
│   │   ├── payment_intents_controller.rb # index, show, new, create, authorize, capture, void, refund
│   │   ├── ledger_controller.rb        # index (ledger resource)
│   │   └── webhooks_controller.rb      # index
│   └── concerns/
│       ├── api_authenticatable.rb
│       ├── paginatable.rb
│       └── structured_logging.rb
├── models/
│   ├── merchant.rb
│   ├── customer.rb
│   ├── payment_method.rb
│   ├── payment_intent.rb
│   ├── transaction.rb
│   ├── ledger_entry.rb
│   ├── idempotency_record.rb
│   ├── webhook_event.rb
│   ├── audit_log.rb
│   └── api_request_stat.rb
├── services/
│   ├── base_service.rb
│   ├── authorize_service.rb
│   ├── capture_service.rb
│   ├── void_service.rb
│   ├── refund_service.rb
│   ├── ledger_service.rb
│   ├── idempotency_service.rb
│   ├── processor_event_service.rb
│   ├── webhook_delivery_service.rb
│   ├── webhook_signature_service.rb
│   ├── audit_log_service.rb
│   ├── metrics_service.rb
│   ├── rate_limiter_service.rb
│   ├── safe_log_helper.rb
│   └── concerns/
│       ├── webhook_triggerable.rb
│       └── auditable.rb
├── jobs/
│   ├── application_job.rb
│   └── webhook_delivery_job.rb
├── middleware/
│   └── request_id_middleware.rb
├── helpers/
│   └── dashboard_helper.rb
└── views/dashboard/
    ├── sessions/new.html.erb
    ├── registrations/new.html.erb
    ├── account/show.html.erb
    ├── overview/index.html.erb
    ├── transactions/index.html.erb
    ├── payment_intents/index.html.erb, show.html.erb, new.html.erb
    ├── ledger/index.html.erb
    └── webhooks/index.html.erb
```

---

## 3. Logical Boundaries (Proposal – Future)

The codebase can be mentally grouped into domains. **No refactor required today**; this is for documentation clarity:

| Domain | Current Location | Key Entities / Services |
|--------|------------------|--------------------------|
| **Payments** | `controllers/`, `models/`, `services/` | PaymentIntent, Transaction, AuthorizeService, CaptureService, VoidService, RefundService |
| **Ledger** | `models/ledger_entry.rb`, `services/ledger_service.rb` | LedgerEntry, LedgerService (charge/refund/fee) |
| **Webhooks** | `models/webhook_event.rb`, `services/`, `jobs/` | WebhookEvent, ProcessorEventService, WebhookDeliveryService, WebhookDeliveryJob |
| **Idempotency** | `models/idempotency_record.rb`, `services/idempotency_service.rb` | IdempotencyRecord, IdempotencyService |
| **Auth** | `models/merchant.rb`, `controllers/` | Merchant, ApiAuthenticatable, sessions, registrations |
| **Observability** | `services/`, `controllers/concerns/` | AuditLogService, MetricsService, RateLimiterService, StructuredLogging |

**Future:** Could be structured as `app/domains/payments/`, `app/domains/ledger/`, etc., but not required for current scope.

---

## 4. Payment Lifecycle (State Machine)

```
                    authorize
     created ──────────────────► authorized
        │                              │
        │ fail                         │ void
        ▼                              ▼
     failed                        canceled

                    capture
     authorized ──────────────────► captured
                                       │
                                       │ refund (partial/full)
                                       ▼
                                   captured (unchanged status)
```

| Status | Valid Transitions |
|--------|-------------------|
| `created` | → `authorized` (authorize success), → `failed` (authorize failure) |
| `authorized` | → `captured` (capture), → `canceled` (void) |
| `captured` | refund creates transaction; status stays `captured` |
| `canceled` | terminal |
| `failed` | terminal |

---

## 5. Service Object Usage

| Action | Service | Idempotency Endpoint | Ledger | Webhook |
|--------|---------|----------------------|--------|---------|
| Authorize | `AuthorizeService.call(payment_intent:, idempotency_key:)` | `authorize` | None | transaction.succeeded / transaction.failed |
| Capture | `CaptureService.call(payment_intent:, idempotency_key:)` | `capture` | charge (positive) | transaction.succeeded / transaction.failed |
| Void | `VoidService.call(payment_intent:, idempotency_key:)` | `void` | None | (AuditLog only) |
| Refund | `RefundService.call(payment_intent:, amount_cents:, idempotency_key:)` | `refund` | refund (negative) | transaction.succeeded / transaction.failed |

**Ledger sign convention:** charges = positive `amount_cents`; refunds = negative `amount_cents`. Fees can be positive or negative.

---

## 6. API vs Dashboard Behavior

| Concern | API | Dashboard |
|---------|-----|-----------|
| Create Payment Intent | Full payload: customer_id, payment_method_id, amount_cents, currency | Amount only; customer + payment_method auto-resolved or created |
| Idempotency | `idempotency_key` in params; IdempotencyService used | Auto-generated per request (SecureRandom.uuid) |
| Auth | `X-API-KEY` | Session (email/password or API key) |

Both call the same services: `AuthorizeService`, `CaptureService`, `VoidService`, `RefundService`.

---

## 7. Key Conventions

- **Merchant scoping:** All queries use `current_merchant.payment_intents`, `current_merchant.customers`, etc. No cross-merchant access.
- **No ledger on authorize/void:** Funds are held on authorize; void releases the hold. Ledger entries only on capture (charge) and refund (negative).
- **Tokenized payment methods:** Only `token`, `last4`, `brand`, `exp_month`, `exp_year` stored. No raw PAN.
- **Processor simulation:** `simulate_processor_authorization`, `simulate_processor_capture`, etc. return random success/failure. Timeout handling exists.

---

## 8. Implementation Plan

Non-breaking steps to align the codebase with this architecture:

1. Add `docs/ARCHITECTURE.md` (this file) to the repo and link from README.
2. Add a short comment block at the top of each service class describing its domain (payments, ledger, webhooks).
3. Extract shared idempotency logic from `Api::V1::PaymentIntentsController` and `Dashboard::PaymentIntentsController` into a private concern or helper (optional; current duplication is acceptable).
4. Document the IdempotencyService endpoint names (`authorize`, `capture`, `void`, `refund`, `create_payment_intent`) in a central place (e.g. `IdempotencyService` or a doc).
5. Add a `docs/` index (e.g. `docs/README.md`) linking ARCHITECTURE, SEQUENCE_DIAGRAMS, DATA_FLOW, SECURITY, DEPLOYMENT.
6. Consider adding `payment_intent_id` to `Transaction`-level idempotency `request_params` consistently (already done; verify).
7. Ensure `LedgerEntry` `entry_type` is always one of `charge`, `refund`, `fee` (already enforced by validation).
