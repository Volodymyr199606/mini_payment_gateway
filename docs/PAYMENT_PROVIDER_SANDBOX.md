# Payment Provider Sandbox Integration

This app supports two provider modes:

- **simulated** (default) – no external calls, deterministic for local/dev/test
- **stripe_sandbox** – real Stripe test-mode API calls

## Configuration

### Environment variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `PAYMENTS_PROVIDER` | No | `simulated` | `simulated` or `stripe_sandbox` |
| `STRIPE_SECRET_KEY` | Yes (for stripe_sandbox) | — | Stripe test secret key (`sk_test_...`) |
| `STRIPE_WEBHOOK_SECRET` | Yes (for stripe_sandbox) | — | Webhook signing secret (`whsec_...`) |
| `STRIPE_BASE_URL` | No | `https://api.stripe.com` | Override for Stripe API base |
| `PROCESSOR_TIMEOUT_SECONDS` | No | `3` | Timeout for provider API calls |

Startup validation runs from `config/initializers/payments_provider_config.rb`. In development and test, invalid provider config raises immediately.

## Runtime behavior

- Internal payment lifecycle and domain models (`PaymentIntent`, `Transaction`, `LedgerEntry`) remain unchanged.
- Services call the active provider adapter for processor-facing actions.
- Ledger, idempotency, audit, and merchant scoping stay in existing services.
- Stripe adapter uses `PROCESSOR_TIMEOUT_SECONDS` for Faraday timeouts; Faraday/network errors are mapped to `Payments::ProviderRequestError`.

## Stripe sandbox mapping

| Internal action | Stripe API |
|-----------------|------------|
| Authorize | Create PaymentIntent with `capture_method=manual`, `confirm=true` |
| Capture | `POST /v1/payment_intents/:id/capture` |
| Void | `POST /v1/payment_intents/:id/cancel` |
| Refund | `POST /v1/refunds` (payment_intent, amount) |

Provider IDs (e.g. `pi_xxx`) are stored in `transactions.processor_ref`. The authorize transaction’s `processor_ref` is used for capture, void, and refund.

**Payment method:** Stripe expects `pm_card_visa` or a real Stripe PM ID. Internal `PaymentMethod` tokens are `pm_<hex>`; for sandbox, store `pm_card_visa` in `token` or use Stripe test PM IDs.

## Webhooks

`POST /api/v1/webhooks/processor` delegates to the active provider adapter for:

1. **Signature verification** – Stripe: `Stripe-Signature` header, timestamp tolerance 300s
2. **Event normalization** – Maps provider events to internal (`transaction.succeeded`, `chargeback.opened`, etc.)
3. **Idempotent ingestion** – `provider_event_id` (e.g. Stripe `evt_xxx`) prevents duplicate processing; replays return `200` with `already_received`
4. **Chargeback lookup** – Resolves `payment_intent_id` from metadata or `provider_payment_intent_id` (lookup by `processor_ref`)

### Testing webhooks locally with Stripe

1. Install [Stripe CLI](https://stripe.com/docs/stripe-cli)
2. Run `stripe listen --forward-to localhost:3000/api/v1/webhooks/processor`
3. Use the printed webhook signing secret as `STRIPE_WEBHOOK_SECRET`
4. Trigger test events: `stripe trigger payment_intent.succeeded`

### Simulated webhooks

With `PAYMENTS_PROVIDER=simulated`, use `X-WEBHOOK-SIGNATURE` and the app’s `webhook_secret` (see `WebhookSignatureService`).

## What remains simulated vs real

| Area | Simulated | Stripe sandbox |
|------|-----------|----------------|
| Authorize/Capture/Void/Refund | Random success/failure | Real Stripe API |
| Webhook signature | HMAC vs `webhook_secret` | Stripe `Stripe-Signature` |
| Ledger, audit, idempotency | Same | Same |
| Card data | None | Stripe test cards |

## Testing

- CI is deterministic; no real external API calls.
- Specs stub the provider via `Payments::ProviderRegistry.current` or `InvariantsPaymentHelpers#stub_successful_provider`.
- Simulated mode is first-class for fast local development and demos.
