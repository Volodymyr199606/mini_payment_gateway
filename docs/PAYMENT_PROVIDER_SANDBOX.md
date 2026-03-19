# Payment Provider Sandbox Integration

This app supports two provider modes:

- `simulated` (default)
- `stripe_sandbox`

## Configuration

Set environment variables:

```bash
PAYMENTS_PROVIDER=simulated
```

or

```bash
PAYMENTS_PROVIDER=stripe_sandbox
STRIPE_SECRET_KEY=sk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
# Optional override
STRIPE_BASE_URL=https://api.stripe.com
```

Startup validation runs from `config/initializers/payments_provider_config.rb`.
In development/test, invalid provider config raises immediately with a clear message.

## Runtime behavior

- Internal payment lifecycle remains unchanged.
- Services call provider adapters for processor-facing actions.
- Internal records (`Transaction`, `PaymentIntent`, `LedgerEntry`) are still written by current service logic.

## Stripe sandbox mapping

- Authorize: Stripe PaymentIntent (`capture_method=manual`, `confirm=true`)
- Capture: Stripe PaymentIntent capture
- Void: Stripe PaymentIntent cancel
- Refund: Stripe refund API

Provider IDs are mapped into `transactions.processor_ref`.

## Webhooks

`POST /api/v1/webhooks/processor` now delegates to active provider adapter:

- signature verification
- event normalization
- persistence to `WebhookEvent`

For Stripe sandbox, pass `Stripe-Signature` header and Stripe event payload.

## Testing

- CI remains deterministic and does not call real external APIs.
- Specs stub provider adapter behavior via `Payments::ProviderRegistry.current`.
- Simulated mode remains first-class for fast local development and demos.
