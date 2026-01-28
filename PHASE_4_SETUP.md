# Phase 4: Webhooks + Async - Complete

## Commands to Run

```bash
# No new dependencies - just restart server if running
rails server

# Optional: Set webhook secret (or use default for development)
export WEBHOOK_SECRET="your_secret_key_here"
```

## Webhook System Overview

The webhook system simulates a payment processor sending events to merchants:
1. **Processor Events**: Simulated events (transaction.succeeded, transaction.failed, chargeback.opened)
2. **Signature Verification**: HMAC-SHA256 signature verification for security
3. **Event Storage**: All events stored in `webhook_events` table
4. **Async Delivery**: Background jobs deliver webhooks to merchant endpoints
5. **Retry Strategy**: Exponential backoff with max 3 attempts

## Services Created

### 1. WebhookSignatureService
- **Purpose**: Verifies HMAC-SHA256 signatures on incoming webhooks
- **Method**: `generate_signature(payload, secret)` - Class method for generating signatures
- **Security**: Uses `ActiveSupport::SecurityUtils.secure_compare` to prevent timing attacks
- **Secret Source**: `WEBHOOK_SECRET` env var or Rails credentials

### 2. ProcessorEventService
- **Purpose**: Creates processor events and queues them for delivery
- **Event Types**:
  - `transaction.succeeded` - Transaction completed successfully
  - `transaction.failed` - Transaction failed
  - `chargeback.opened` - Chargeback initiated (optional)
- **Process**:
  1. Validates event type
  2. Creates `WebhookEvent` record
  3. Generates HMAC signature
  4. Queues `WebhookDeliveryJob` for async delivery

### 3. WebhookDeliveryService
- **Purpose**: Delivers webhooks to merchant endpoints
- **Features**:
  - HTTP POST delivery with signature headers
  - Retry with exponential backoff (2^attempt seconds)
  - Max 3 attempts before marking as failed
  - Handles missing webhook URLs gracefully (stores for viewing)
- **Headers Sent**:
  - `Content-Type: application/json`
  - `X-WEBHOOK-SIGNATURE: <hmac_signature>`
  - `X-WEBHOOK-EVENT-TYPE: <event_type>`

### 4. WebhookTriggerable Concern
- **Purpose**: Mixin for services to trigger webhook events
- **Usage**: Included in AuthorizeService, CaptureService, RefundService
- **Method**: `trigger_webhook_event(event_type:, transaction:, payment_intent:)`

## Jobs Created

### WebhookDeliveryJob
- **Queue**: `default`
- **Retry**: Exponential backoff, max 3 attempts
- **Process**: 
  1. Finds webhook event
  2. Calls `WebhookDeliveryService`
  3. Handles errors and logging

## Controllers Created

### WebhooksController
- **POST /api/v1/webhooks/processor** - Receives processor events
  - Verifies HMAC signature
  - Parses JSON payload
  - Creates webhook event record
  - Queues delivery job
  - **No authentication required** (processor endpoint)

## Webhook Event Flow

### 1. Transaction Completes
```
AuthorizeService/CaptureService/RefundService
  → trigger_webhook_event()
  → ProcessorEventService.call()
  → Creates WebhookEvent
  → Queues WebhookDeliveryJob
```

### 2. Webhook Delivery
```
WebhookDeliveryJob
  → WebhookDeliveryService.call()
  → HTTP POST to merchant endpoint
  → Updates delivery_status (succeeded/failed)
  → Retries on failure with backoff
```

### 3. Processor Event (Simulated)
```
POST /api/v1/webhooks/processor
  → WebhookSignatureService (verify signature)
  → Creates WebhookEvent
  → Queues WebhookDeliveryJob
```

## Webhook Payload Structure

### transaction.succeeded / transaction.failed
```json
{
  "event_type": "transaction.succeeded",
  "data": {
    "merchant_id": 1,
    "payment_intent_id": 123,
    "transaction_id": 456,
    "transaction_kind": "authorize",
    "transaction_status": "succeeded",
    "amount_cents": 5000,
    "currency": "USD",
    "processor_ref": "txn_abc123",
    "failure_code": null,
    "failure_message": null,
    "created_at": "2026-01-27T12:00:00Z"
  }
}
```

### chargeback.opened
```json
{
  "event_type": "chargeback.opened",
  "data": {
    "merchant_id": 1,
    "payment_intent_id": 123,
    "transaction_id": 456,
    "chargeback_id": "cb_xyz789",
    "reason": "fraudulent",
    "amount_cents": 5000,
    "currency": "USD"
  }
}
```

## Signature Generation

### Server-Side (Processor)
```ruby
payload_json = payload.to_json
signature = WebhookSignatureService.generate_signature(
  payload_json,
  webhook_secret
)
```

### Client-Side (Merchant Verification)
```ruby
# Merchant receives webhook
signature = request.headers["X-WEBHOOK-SIGNATURE"]
payload = request.body.read

# Verify signature
service = WebhookSignatureService.call(
  payload: payload,
  signature: signature
)

if service.success?
  # Process webhook
else
  # Reject webhook
end
```

## Configuration

### Environment Variables
- `WEBHOOK_SECRET` - Secret key for HMAC signature (required in production)
- `MERCHANT_WEBHOOK_URL` - Default webhook URL for testing (optional)

### ActiveJob Configuration
- **Development**: `:async` adapter (in-memory queue)
- **Test**: `:test` adapter (synchronous execution)
- **Production**: Configure with Sidekiq, DelayedJob, or similar

## Testing Webhooks

### 1. Simulate Processor Event
```bash
# Generate signature
payload='{"event_type":"transaction.succeeded","data":{"merchant_id":1}}'
signature=$(echo -n "$payload" | openssl dgst -sha256 -hmac "your_secret" | cut -d' ' -f2)

# Send webhook
curl -X POST http://localhost:3000/api/v1/webhooks/processor \
  -H "Content-Type: application/json" \
  -H "X-WEBHOOK-SIGNATURE: $signature" \
  -d "$payload"
```

### 2. Test Merchant Webhook Endpoint
```bash
# Start a test server to receive webhooks
# In another terminal:
python3 -m http.server 8000

# Set webhook URL
export MERCHANT_WEBHOOK_URL="http://localhost:8000/webhooks"

# Trigger a transaction (webhook will be delivered)
curl -X POST http://localhost:3000/api/v1/payment_intents/1/authorize \
  -H "X-API-KEY: <key>" \
  -H "Content-Type: application/json"
```

## Webhook Event States

- **pending** - Queued for delivery
- **succeeded** - Successfully delivered
- **failed** - Failed after max attempts

## Retry Strategy

- **Attempt 1**: Immediate
- **Attempt 2**: 2 seconds delay (2^1)
- **Attempt 3**: 4 seconds delay (2^2)
- **Max Attempts**: 3
- **After Max**: Marked as `failed`, no further retries

## Files Created

- `app/services/webhook_signature_service.rb`
- `app/services/processor_event_service.rb`
- `app/services/webhook_delivery_service.rb`
- `app/services/concerns/webhook_triggerable.rb`
- `app/jobs/webhook_delivery_job.rb`
- `app/controllers/api/v1/webhooks_controller.rb`
- `config/initializers/webhook_config.rb`

## Files Modified

- `app/services/authorize_service.rb` - Added webhook triggering
- `app/services/capture_service.rb` - Added webhook triggering
- `app/services/refund_service.rb` - Added webhook triggering
- `config/routes.rb` - Added webhook route
- `config/environments/development.rb` - Added ActiveJob async adapter
- `config/environments/test.rb` - Added ActiveJob test adapter

## Security Notes

1. **Signature Verification**: All incoming processor webhooks are verified
2. **Secure Comparison**: Uses timing-attack-resistant comparison
3. **Secret Management**: Use environment variables or Rails credentials in production
4. **HTTPS**: Webhook delivery should use HTTPS in production

## Next Steps (Phase 5)

- Structured logging with request_id, merchant_id, etc.
- Rate limiting per merchant
- Audit log on major actions
- Webhook retry improvements
- Observability metrics
