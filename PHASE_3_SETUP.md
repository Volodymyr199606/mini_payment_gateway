# Phase 3: Service Objects, Idempotency, Ledger Writes - Complete

## Commands to Run

```bash
# No new dependencies - just restart server if running
rails server
```

## Service Objects Created

### 1. BaseService
- Base class for all service objects
- Provides `call` class method pattern
- Error handling with `errors` array
- Success/failure checking methods

### 2. IdempotencyService
- **Purpose**: Prevents duplicate requests using idempotency keys
- **Usage**: Checks if request with same merchant + key + endpoint was already processed
- **Features**:
  - Returns cached response if found
  - Stores response after successful operation
  - Uses SHA256 hash of request params for comparison

### 3. AuthorizeService
- **Purpose**: Authorizes a payment intent
- **State Validation**: Payment intent must be in `created` state
- **Process**:
  1. Validates state
  2. Simulates processor authorization (90% success rate)
  3. Creates authorize transaction
  4. Updates payment intent status to `authorized` or `failed`
  5. Creates ledger entry for charge (authorization holds funds)
- **Returns**: Transaction and updated payment intent

### 4. CaptureService
- **Purpose**: Captures an authorized payment
- **State Validation**: Payment intent must be in `authorized` state
- **Process**:
  1. Validates state
  2. Checks for existing capture (prevents double-capture)
  3. Simulates processor capture (95% success rate)
  4. Creates capture transaction
  5. Updates payment intent status to `captured`
  6. Creates ledger entry for charge
- **Returns**: Transaction and updated payment intent

### 5. VoidService
- **Purpose**: Voids a payment intent (cancels authorization)
- **State Validation**: Payment intent must be in `created` or `authorized` state
- **Process**:
  1. Validates state
  2. Simulates processor void (98% success rate)
  3. Creates void transaction
  4. Updates payment intent status to `canceled`
  5. Creates ledger entry for refund (if was authorized)
- **Returns**: Transaction and updated payment intent

### 6. RefundService
- **Purpose**: Refunds a captured payment
- **State Validation**: Payment intent must be in `captured` state
- **Process**:
  1. Validates state
  2. Determines refund amount (defaults to full refundable amount)
  3. Validates refund amount doesn't exceed refundable amount
  4. Simulates processor refund (99% success rate)
  5. Creates refund transaction
  6. Creates ledger entry for refund (negative amount)
- **Returns**: Transaction, updated payment intent, and refund amount

### 7. LedgerService
- **Purpose**: Creates ledger entries for money movement
- **Entry Types**: `charge`, `refund`, `fee`
- **Convention**: Positive amounts for charges, negative for refunds
- **Usage**: Called automatically by other services

## Idempotency Implementation

### How It Works
1. Client sends request with `idempotency_key` parameter
2. `IdempotencyService` checks for existing record with:
   - Same merchant
   - Same idempotency key
   - Same endpoint
   - Same request hash (SHA256 of params)
3. If found: Returns cached response immediately
4. If not found: Processes request and stores response

### Supported Endpoints
- `create_payment_intent` - Payment intent creation
- `authorize` - Authorization
- `capture` - Capture
- `void` - Void
- `refund` - Refund

### Usage Example
```bash
# First request
curl -X POST http://localhost:3000/api/v1/payment_intents/1/authorize \
  -H "X-API-KEY: <key>" \
  -H "Content-Type: application/json" \
  -d '{"idempotency_key": "auth_001"}'

# Retry with same key - returns cached response
curl -X POST http://localhost:3000/api/v1/payment_intents/1/authorize \
  -H "X-API-KEY: <key>" \
  -H "Content-Type: application/json" \
  -d '{"idempotency_key": "auth_001"}'
```

## State Machine Rules

### Payment Intent States
- **created** → **authorized** (via authorize)
- **created** → **canceled** (via void)
- **created** → **failed** (authorization fails)
- **authorized** → **captured** (via capture)
- **authorized** → **canceled** (via void)
- **captured** → (refundable, but status stays captured)

### Transaction Rules
- Cannot capture unless intent is authorized
- Cannot refund unless intent is captured
- Cannot double-capture (checked in CaptureService)
- Partial refunds allowed (tracked via `refundable_cents`)

## Ledger Entry Creation

### When Ledger Entries Are Created

1. **Authorization**:
   - Entry type: `charge`
   - Amount: Positive (authorization holds funds)

2. **Capture**:
   - Entry type: `charge`
   - Amount: Positive (finalizes charge)

3. **Void (if authorized)**:
   - Entry type: `refund`
   - Amount: Negative (releases held funds)

4. **Refund**:
   - Entry type: `refund`
   - Amount: Negative (returns funds)

### Ledger Entry Structure
```ruby
{
  merchant_id: 1,
  transaction_id: 123,
  entry_type: "charge" | "refund" | "fee",
  amount_cents: 5000,  # Positive for charges, negative for refunds
  currency: "USD"
}
```

## Controllers Updated

### PaymentIntentsController
- `create` - Added idempotency checking
- `authorize` - Uses `AuthorizeService` with idempotency
- `capture` - Uses `CaptureService` with idempotency
- `void` - Uses `VoidService` with idempotency
- Added `serialize_transaction` helper

### RefundsController
- `create` - Uses `RefundService` with idempotency
- Added serialization helpers

## Processor Simulation

All services simulate external payment processor calls with:
- **Authorization**: 90% success rate
- **Capture**: 95% success rate
- **Void**: 98% success rate
- **Refund**: 99% success rate

In production, these would call actual payment processor APIs (Stripe, Braintree, etc.).

## Error Handling

Services use `BaseService` pattern:
- Return service object with `success?` / `failure?` methods
- Errors stored in `errors` array
- Controllers check `service.success?` and render appropriate responses

## Files Created

- `app/services/base_service.rb`
- `app/services/idempotency_service.rb`
- `app/services/authorize_service.rb`
- `app/services/capture_service.rb`
- `app/services/void_service.rb`
- `app/services/refund_service.rb`
- `app/services/ledger_service.rb`

## Files Modified

- `app/controllers/api/v1/payment_intents_controller.rb` - Integrated all service objects
- `app/controllers/api/v1/refunds_controller.rb` - Integrated RefundService

## Example API Flow

### Complete Payment Flow
```bash
# 1. Create payment intent
POST /api/v1/payment_intents
{
  "payment_intent": {
    "customer_id": 1,
    "payment_method_id": 1,
    "amount_cents": 5000,
    "currency": "USD",
    "idempotency_key": "intent_001"
  }
}

# 2. Authorize
POST /api/v1/payment_intents/1/authorize
{
  "idempotency_key": "auth_001"
}

# 3. Capture
POST /api/v1/payment_intents/1/capture
{
  "idempotency_key": "capture_001"
}

# 4. Refund (partial)
POST /api/v1/payment_intents/1/refunds
{
  "refund": {
    "amount_cents": 2000
  },
  "idempotency_key": "refund_001"
}
```

## Next Steps (Phase 4)

- Webhook receiver endpoint
- Processor event simulator
- Webhook signature verification
- Async webhook delivery (optional)
- Webhook retry strategy
