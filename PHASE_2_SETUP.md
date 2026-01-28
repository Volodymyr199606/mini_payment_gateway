# Phase 2: Controllers, Routes, Serializers, Pagination, Error Handling - Complete

## Commands to Run

```bash
# 1. Install new gem (kaminari for pagination)
bundle install

# 2. Restart server if running
rails server
```

## Controllers Created

### 1. MerchantsController
- **POST /api/v1/merchants** - Create merchant (no auth required)
  - Returns merchant with plaintext API key (only shown once)
  - Used for bootstrap/dev setup
- **GET /api/v1/merchants/me** - Get current merchant (auth required)
  - Returns authenticated merchant details

### 2. CustomersController
- **POST /api/v1/customers** - Create customer
  - Requires: `customer[email]`, optional: `customer[name]`
- **GET /api/v1/customers** - List customers (paginated)
  - Query params: `page`, `per_page` (max 100, default 25)
- **GET /api/v1/customers/:id** - Show customer
  - Returns customer details

### 3. PaymentMethodsController
- **POST /api/v1/customers/:customer_id/payment_methods** - Create payment method
  - Requires: `payment_method[method_type]`
  - Optional: `last4`, `brand`, `exp_month`, `exp_year`
  - Auto-generates token

### 4. PaymentIntentsController
- **POST /api/v1/payment_intents** - Create payment intent
  - Requires: `payment_intent[customer_id]`, `payment_intent[amount_cents]`
  - Optional: `payment_intent[payment_method_id]`, `payment_intent[currency]`, `payment_intent[idempotency_key]`, `payment_intent[metadata]`
- **GET /api/v1/payment_intents** - List payment intents (paginated)
- **GET /api/v1/payment_intents/:id** - Show payment intent
- **POST /api/v1/payment_intents/:id/authorize** - Authorize payment (Phase 3)
- **POST /api/v1/payment_intents/:id/capture** - Capture payment (Phase 3)
- **POST /api/v1/payment_intents/:id/void** - Void payment (Phase 3)

### 5. RefundsController
- **POST /api/v1/payment_intents/:payment_intent_id/refunds** - Create refund
  - Optional: `refund[amount_cents]` (defaults to full refundable amount)
  - Validates refundable amount (Phase 3)

## Features Implemented

### Pagination
- **Concern**: `Paginatable` module
- **Gem**: Kaminari
- **Defaults**: 25 per page, max 100
- **Response format**:
  ```json
  {
    "data": [...],
    "meta": {
      "page": 1,
      "per_page": 25,
      "total": 100,
      "total_pages": 4
    }
  }
  ```

### Error Handling
- **Consistent error format**:
  ```json
  {
    "error": {
      "code": "error_code",
      "message": "Human readable message",
      "details": {}
    }
  }
  ```
- **Error codes**:
  - `unauthorized` - Missing/invalid API key
  - `validation_error` - Record validation failed
  - `not_found` - Resource not found
  - `invalid_state` - Invalid state transition
  - `parameter_missing` - Required parameter missing
  - `internal_error` - Unexpected server error
  - `not_implemented` - Endpoint not yet implemented (Phase 3)

### Request Validation
- Parameter validation via `params.require().permit()`
- Merchant ownership validation (customers, payment intents)
- Customer-payment method relationship validation
- State validation for authorize/capture/void/refund

### Serialization
- Inline serializers in each controller
- Consistent JSON structure with `data` wrapper
- Includes related resource IDs and computed fields

## Routes

All routes are under `/api/v1` namespace:

```
GET    /api/v1/health
POST   /api/v1/merchants
GET    /api/v1/merchants/me
GET    /api/v1/customers
POST   /api/v1/customers
GET    /api/v1/customers/:id
POST   /api/v1/customers/:customer_id/payment_methods
GET    /api/v1/payment_intents
POST   /api/v1/payment_intents
GET    /api/v1/payment_intents/:id
POST   /api/v1/payment_intents/:id/authorize
POST   /api/v1/payment_intents/:id/capture
POST   /api/v1/payment_intents/:id/void
POST   /api/v1/payment_intents/:payment_intent_id/refunds
```

## Example API Requests

### Create Merchant
```bash
curl -X POST http://localhost:3000/api/v1/merchants \
  -H "Content-Type: application/json" \
  -d '{"name": "Test Merchant"}'
```

### Create Customer
```bash
curl -X POST http://localhost:3000/api/v1/customers \
  -H "Content-Type: application/json" \
  -H "X-API-KEY: <your-api-key>" \
  -d '{"customer": {"email": "test@example.com", "name": "Test User"}}'
```

### List Customers (Paginated)
```bash
curl http://localhost:3000/api/v1/customers?page=1&per_page=10 \
  -H "X-API-KEY: <your-api-key>"
```

### Create Payment Intent
```bash
curl -X POST http://localhost:3000/api/v1/payment_intents \
  -H "Content-Type: application/json" \
  -H "X-API-KEY: <your-api-key>" \
  -d '{
    "payment_intent": {
      "customer_id": 1,
      "payment_method_id": 1,
      "amount_cents": 5000,
      "currency": "USD",
      "idempotency_key": "intent_001"
    }
  }'
```

## Files Created/Modified

### New Files
- `app/controllers/api/v1/merchants_controller.rb`
- `app/controllers/api/v1/customers_controller.rb`
- `app/controllers/api/v1/payment_methods_controller.rb`
- `app/controllers/api/v1/payment_intents_controller.rb`
- `app/controllers/api/v1/refunds_controller.rb`
- `app/controllers/concerns/paginatable.rb`
- `config/initializers/kaminari_config.rb`

### Modified Files
- `Gemfile` - Added kaminari gem
- `config/routes.rb` - Added all API routes
- `app/controllers/api/v1/base_controller.rb` - Added error handlers

## Notes

- **Phase 3 Placeholders**: authorize, capture, void, and refund endpoints return `not_implemented` errors. They will be implemented in Phase 3 with service objects.
- **State Validation**: Payment intent state transitions are validated but not yet enforced (Phase 3).
- **Idempotency**: Idempotency key validation exists but full idempotency logic will be in Phase 3.

## Next Steps (Phase 3)

- Implement service objects for authorize/capture/void/refund
- Add idempotency checking
- Create ledger entries on transactions
- Enforce state machine rules
- Handle transaction failures
