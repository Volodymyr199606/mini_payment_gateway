# Phase 5: Observability - Complete

## Commands to Run

```bash
# No new dependencies - just restart server if running
rails server
```

## Features Implemented

### 1. Structured Logging
- **Request ID Middleware**: Generates unique request IDs for each request
- **Structured Logging Concern**: JSON-formatted logs with consistent structure
- **Log Fields**: request_id, merchant_id, transaction_id, payment_intent_id, duration_ms, etc.
- **Event Types**: request_started, request_completed, request_error, transaction events

### 2. Rate Limiting
- **Per-Merchant Rate Limiting**: 100 requests per 60 seconds (configurable)
- **Rate Limit Headers**: X-RateLimit-Limit, X-RateLimit-Remaining, X-RateLimit-Reset
- **Response**: 429 Too Many Requests when limit exceeded
- **Storage**: Uses Rails cache (memory in dev, Redis in production)

### 3. Audit Logging
- **Automatic Audit Logs**: Created for all major payment operations
- **Actions Logged**:
  - `payment_authorized` / `payment_authorization_failed`
  - `payment_captured` / `payment_capture_failed`
  - `payment_voided` / `payment_void_failed`
  - `payment_refunded` / `payment_refund_failed`
- **Metadata**: Includes transaction details, amounts, status, failure codes
- **Request Tracking**: Includes request_id for traceability

## Components Created

### 1. RequestIdMiddleware
- **Location**: `app/middleware/request_id_middleware.rb`
- **Function**: 
  - Generates UUID request IDs
  - Accepts `X-Request-ID` header from clients
  - Adds `X-Request-ID` to response headers
  - Stores in thread-local storage for logging

### 2. StructuredLogging Concern
- **Location**: `app/controllers/concerns/structured_logging.rb`
- **Features**:
  - Around-action logging (request_started, request_completed)
  - JSON-formatted log entries
  - Includes merchant_id, request_id, duration_ms
  - Helper method: `log_transaction_event`

### 3. RateLimiterService
- **Location**: `app/services/rate_limiter_service.rb`
- **Configuration**:
  - Default: 100 requests per 60 seconds
  - Configurable per merchant
  - Uses Rails cache for storage
- **Returns**: `{ limited: bool, remaining: int, reset_at: Time }`

### 4. AuditLogService
- **Location**: `app/services/audit_log_service.rb`
- **Features**:
  - Creates audit log records
  - Includes actor (merchant), action, auditable (transaction/intent)
  - Stores metadata (JSONB)
  - Non-blocking (errors don't fail main operation)

### 5. Auditable Concern
- **Location**: `app/services/concerns/auditable.rb`
- **Usage**: Included in payment services
- **Method**: `create_audit_log(action:, auditable:, metadata:)`

## Log Format

### Request Logs
```json
{
  "event": "request_started",
  "method": "POST",
  "path": "/api/v1/payment_intents/1/authorize",
  "merchant_id": 1,
  "request_id": "550e8400-e29b-41d4-a716-446655440000",
  "timestamp": "2026-01-27T12:00:00Z",
  "service": "mini_payment_gateway"
}
```

### Transaction Logs
```json
{
  "event": "transaction_authorized",
  "transaction_id": 123,
  "payment_intent_id": 456,
  "merchant_id": 1,
  "transaction_kind": "authorize",
  "transaction_status": "succeeded",
  "amount_cents": 5000,
  "request_id": "550e8400-e29b-41d4-a716-446655440000",
  "timestamp": "2026-01-27T12:00:00Z",
  "service": "mini_payment_gateway"
}
```

### Error Logs
```json
{
  "event": "request_error",
  "error": "StandardError",
  "message": "Something went wrong",
  "backtrace": ["...", "..."],
  "merchant_id": 1,
  "request_id": "550e8400-e29b-41d4-a716-446655440000",
  "timestamp": "2026-01-27T12:00:00Z",
  "service": "mini_payment_gateway"
}
```

## Rate Limiting

### Headers
- `X-RateLimit-Limit`: Maximum requests allowed (100)
- `X-RateLimit-Remaining`: Remaining requests in window
- `X-RateLimit-Reset`: Unix timestamp when limit resets

### Response (429 Too Many Requests)
```json
{
  "error": {
    "code": "rate_limit_exceeded",
    "message": "Rate limit exceeded. Limit: 100 requests per 60 seconds"
  }
}
```

### Configuration
```ruby
# Per-merchant configuration (future enhancement)
RateLimiterService.call(
  merchant: merchant,
  limit: 200,  # Custom limit
  window: 120  # 2 minutes
)
```

## Audit Logs

### Example Audit Log Entry
```ruby
{
  merchant_id: 1,
  actor_type: "merchant",
  actor_id: 1,
  action: "payment_authorized",
  auditable_type: "Transaction",
  auditable_id: 123,
  metadata: {
    payment_intent_id: 456,
    amount_cents: 5000,
    status: "succeeded",
    request_id: "550e8400-e29b-41d4-a716-446655440000",
    timestamp: "2026-01-27T12:00:00Z"
  }
}
```

### Querying Audit Logs
```ruby
# All actions for a merchant
AuditLog.for_merchant(merchant)

# All actions for a payment intent
AuditLog.for_auditable(payment_intent)

# Specific action
AuditLog.where(action: "payment_authorized")
```

## Request ID Usage

### Client-Side
```bash
# Send request with custom ID
curl -X POST http://localhost:3000/api/v1/payment_intents/1/authorize \
  -H "X-API-KEY: <key>" \
  -H "X-Request-ID: my-custom-id-123"

# Response includes request ID
# X-Request-ID: my-custom-id-123
```

### Server-Side
- Automatically generated if not provided
- Included in all log entries
- Stored in audit logs
- Available in thread-local storage: `Thread.current[:request_id]`

## Files Created

- `app/middleware/request_id_middleware.rb`
- `app/controllers/concerns/structured_logging.rb`
- `app/services/rate_limiter_service.rb`
- `app/services/audit_log_service.rb`
- `app/services/concerns/auditable.rb`

## Files Modified

- `config/application.rb` - Added RequestIdMiddleware
- `app/controllers/api/v1/base_controller.rb` - Added rate limiting and structured logging
- `app/services/authorize_service.rb` - Added audit logging
- `app/services/capture_service.rb` - Added audit logging
- `app/services/void_service.rb` - Added audit logging
- `app/services/refund_service.rb` - Added audit logging

## Observability Benefits

1. **Traceability**: Request IDs link logs across services
2. **Debugging**: Structured logs make it easy to filter and search
3. **Monitoring**: Rate limit headers help clients manage usage
4. **Compliance**: Audit logs provide complete transaction history
5. **Performance**: Duration tracking helps identify slow endpoints

## Production Considerations

1. **Log Aggregation**: Use services like ELK, Datadog, or CloudWatch
2. **Rate Limiting**: Use Redis for distributed rate limiting
3. **Audit Log Retention**: Implement retention policies
4. **Request ID Propagation**: Pass request IDs to external services
5. **Log Sampling**: Consider sampling for high-volume endpoints

## Next Steps (Phase 6 - Optional Dashboard)

- Simple Rails views or React dashboard
- Merchant login
- List transactions with filters
- Show ledger totals (net, refunds, fees)
- View audit logs
- Webhook event viewer
