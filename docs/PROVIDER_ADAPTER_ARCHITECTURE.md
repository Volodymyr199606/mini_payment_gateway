# Payment Provider Adapter Architecture

This project keeps the internal payment domain stable while allowing multiple processor modes:

- `simulated` (default, deterministic/local-friendly)
- `stripe_sandbox` (real external sandbox provider)

## Design goals

- Keep controllers and domain entities unchanged (`PaymentIntent`, `Transaction`, `LedgerEntry`, `WebhookEvent`, `IdempotencyRecord`)
- Route provider-specific calls through one adapter contract
- Keep ledger, idempotency, audit, and merchant scoping owned by existing services
- Make it easy to add more providers (e.g. `braintree_sandbox`) later

## Core components

- `Payments::Config` (`app/services/payments/config.rb`)
  - Central runtime config (`PAYMENTS_PROVIDER`, Stripe keys/secrets)
  - Startup validation with explicit errors in dev/test
- `Payments::ProviderRegistry` (`app/services/payments/provider_registry.rb`)
  - Returns active adapter instance for current runtime
- `Payments::Providers::BaseAdapter`
  - Explicit provider contract:
    - `authorize`
    - `capture`
    - `void`
    - `refund`
    - `fetch_status`
    - `verify_webhook_signature`
    - `normalize_webhook_event`
- `Payments::Providers::SimulatedAdapter`
  - Maintains existing simulated behavior
- `Payments::Providers::StripeAdapter`
  - Implements Stripe sandbox API + webhook normalization

## Service integration

Payment lifecycle services call `payment_provider` from `BaseService`:

- `AuthorizeService`
- `CaptureService`
- `VoidService`
- `RefundService`

Those services still control:

- state transitions
- transaction persistence
- ledger writes
- audit logs
- webhook event creation

Provider adapters only return normalized operation outcomes (`Payments::ProviderResult`) and never mutate internal domain records directly.

## Webhook integration

`Api::V1::WebhooksController#processor` now:

1. verifies signature via active provider adapter
2. normalizes provider payload into internal event shape
3. persists `WebhookEvent`
4. routes through existing delivery flow

This keeps inbound provider handling explicit and testable.
