# Payment Provider Adapter Architecture

This project keeps the internal payment domain stable while allowing multiple processor modes:

- **simulated** (default) – deterministic, no external calls
- **stripe_sandbox** – real Stripe test-mode API

## Design goals

- Keep controllers and domain entities unchanged (`PaymentIntent`, `Transaction`, `LedgerEntry`, `WebhookEvent`, `IdempotencyRecord`)
- Route provider-specific logic through a single adapter contract
- Keep ledger, idempotency, audit, and merchant scoping in existing services
- Map provider failures to `Payments::ProviderRequestError` so services handle them consistently
- Make it easy to add more providers (e.g. `braintree_sandbox`) later

## Adapter contract (`Payments::Providers::BaseAdapter`)

| Method | Parameters | Returns |
|--------|------------|---------|
| `authorize` | `payment_intent:` | `ProviderResult` |
| `capture` | `payment_intent:` | `ProviderResult` |
| `void` | `payment_intent:` | `ProviderResult` |
| `refund` | `payment_intent:`, `amount_cents:` | `ProviderResult` |
| `fetch_status` | `payment_intent:` | `ProviderResult` |
| `verify_webhook_signature` | `payload:`, `headers:` | Boolean |
| `normalize_webhook_event` | `payload:`, `headers:` | Hash (`:event_type`, `:merchant_id`, `:payload`, `:signature`, `:provider_event_id`) |

`ProviderResult` exposes `success?`, `processor_ref`, `failure_code`, `failure_message`, `provider_status`.

## Core components

- **Payments::Config** (`app/services/payments/config.rb`)
  - `provider`, `timeout_seconds`, Stripe keys
  - `validate!` fails fast in dev/test
- **Payments::ProviderRegistry**
  - `current` returns cached adapter; `reset!` clears cache (used in `to_prepare`)
  - `build(provider_name)` instantiates adapter
- **Payments::Providers::SimulatedAdapter**
  - Probabilistic success/failure; no external calls
- **Payments::Providers::StripeAdapter**
  - Faraday client with timeout; maps Faraday errors to `ProviderRequestError`
  - Webhook: `Stripe-Signature`, 300s tolerance; chargebacks via `charge.payment_intent` or `processor_ref` lookup

## Service integration

`AuthorizeService`, `CaptureService`, `VoidService`, `RefundService` use `BaseService#payment_provider` (→ `ProviderRegistry.current`). They:

- Validate state before calling the provider
- Wrap provider calls in `Timeout.timeout`
- Rescue `Timeout::Error` and `Payments::ProviderRequestError`
- Create `Transaction`, update `PaymentIntent`, write ledger, audit, webhooks

Adapters do not touch internal domain records.

## Webhook integration

`Api::V1::WebhooksController#processor`:

1. Verifies signature via active adapter
2. Parses JSON payload
3. Normalizes event via adapter
4. **Idempotent:** if `provider_event_id` present and already stored → returns `200` with `already_received`
5. Creates `WebhookEvent` with `provider_event_id`
6. For `chargeback.opened`, resolves `PaymentIntent` from metadata or `provider_payment_intent_id` (lookup by `processor_ref`), updates `dispute_status`
7. Enqueues `WebhookDeliveryJob`

## Testing

- **Provider contract:** `spec/support/provider_adapter_contract.rb` shared examples
- **ProviderRegistry:** `spec/services/payments/provider_registry_spec.rb`
- **StripeAdapter:** `spec/services/payments/stripe_adapter_spec.rb` (signature, normalization, missing-ref behavior)
- **Webhooks:** `spec/requests/webhooks_provider_spec.rb` (signature, persistence, duplicate `provider_event_id`)
