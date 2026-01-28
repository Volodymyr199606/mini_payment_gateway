# Phase 1: Models, Migrations, Associations, Validations, Seeds - Complete

## Commands to Run

```bash
# 1. Run migrations
rails db:migrate

# 2. Seed the database
rails db:seed

# Note: The seed script will output API keys for test merchants.
# Save them - they won't be shown again!
```

## Models Created

### 1. Merchant
- **Fields**: `name`, `api_key_digest` (hashed), `status` (active/inactive)
- **Methods**: 
  - `self.generate_api_key` - Generates random 64-char hex string
  - `self.create_with_api_key(attributes)` - Creates merchant and returns [merchant, plaintext_key]
  - `self.find_by_api_key(api_key)` - Finds merchant by API key
  - `api_key_matches?(api_key)` - Validates API key
- **Associations**: customers, payment_intents, ledger_entries, webhook_events, audit_logs, idempotency_records
- **Validations**: name presence, status inclusion, api_key_digest uniqueness

### 2. Customer
- **Fields**: `merchant_id`, `email`, `name`
- **Associations**: belongs_to merchant, has_many payment_methods, payment_intents
- **Validations**: email presence & format, email uniqueness per merchant

### 3. PaymentMethod
- **Fields**: `customer_id`, `method_type`, `last4`, `brand`, `exp_month`, `exp_year`, `token` (unique)
- **Associations**: belongs_to customer, has_many payment_intents
- **Validations**: method_type inclusion, token uniqueness, last4 length, exp_month/year ranges
- **Callbacks**: Auto-generates token on create (format: `pm_<hex>`)

### 4. PaymentIntent
- **Fields**: `merchant_id`, `customer_id`, `payment_method_id` (optional), `amount_cents`, `currency`, `status`, `idempotency_key`, `metadata` (jsonb)
- **Associations**: belongs_to merchant, customer, payment_method (optional), has_many transactions
- **Validations**: amount_cents > 0, currency length, status inclusion, idempotency_key uniqueness per merchant
- **Statuses**: created, authorized, captured, canceled, failed
- **Methods**: 
  - `amount` - Returns amount in dollars
  - `total_refunded_cents` - Sum of successful refund transactions
  - `refundable_cents` - Calculates refundable amount (captured - refunded)

### 5. Transaction
- **Fields**: `payment_intent_id`, `kind`, `status`, `amount_cents`, `processor_ref`, `failure_code`, `failure_message`
- **Associations**: belongs_to payment_intent, has_one merchant (through), has_one ledger_entry
- **Validations**: kind/status inclusion, amount_cents > 0, processor_ref uniqueness
- **Kinds**: authorize, capture, void, refund
- **Statuses**: succeeded, failed
- **Callbacks**: Auto-generates processor_ref on create (format: `txn_<hex>`)

### 6. LedgerEntry
- **Fields**: `merchant_id`, `transaction_id` (optional), `entry_type`, `amount_cents`, `currency`
- **Associations**: belongs_to merchant, transaction (optional)
- **Validations**: entry_type inclusion, amount_cents presence, currency length
- **Entry Types**: charge, refund, fee
- **Convention**: Positive amounts for charges, negative for refunds

### 7. WebhookEvent
- **Fields**: `merchant_id` (optional), `event_type`, `payload` (jsonb), `signature`, `delivered_at`, `delivery_status`, `attempts`
- **Associations**: belongs_to merchant (optional)
- **Validations**: event_type presence, payload presence, delivery_status inclusion, attempts >= 0
- **Delivery Statuses**: pending, succeeded, failed

### 8. AuditLog
- **Fields**: `merchant_id` (optional), `actor_type`, `actor_id`, `action`, `auditable_type`, `auditable_id`, `metadata` (jsonb)
- **Associations**: belongs_to merchant (optional)
- **Validations**: actor_type presence, action presence
- **Scopes**: `for_merchant`, `for_auditable`

### 9. IdempotencyRecord
- **Fields**: `merchant_id`, `idempotency_key`, `endpoint`, `request_hash`, `response_body` (jsonb), `status_code`
- **Associations**: belongs_to merchant
- **Validations**: All fields required, idempotency_key + endpoint unique per merchant
- **Purpose**: Prevents duplicate requests when same merchant + key + endpoint is retried

## Migrations

All migrations include:
- Proper foreign keys with `dependent: :destroy` or `nullify` where appropriate
- Indexes on foreign keys and frequently queried fields
- Unique constraints where needed (tokens, idempotency keys)
- Default values for status fields

## Authentication Update

`ApiAuthenticatable` concern now uses `Merchant.find_by_api_key(api_key)` to authenticate requests.

## Seed Data

The seed script creates:
- 2 active merchants (with API keys printed to console)
- 3 customers (2 for merchant1, 1 for merchant2)
- 3 payment methods (one per customer)
- 3 payment intents (created, authorized, captured states)
- 3 transactions (authorize, authorize, capture)
- 3 ledger entries (charges)

**⚠️ Important**: API keys are only shown once during seeding. Save them for testing!

## Database Schema Summary

```
merchants (id, name, api_key_digest, status, timestamps)
customers (id, merchant_id, email, name, timestamps)
payment_methods (id, customer_id, method_type, last4, brand, exp_month, exp_year, token, timestamps)
payment_intents (id, merchant_id, customer_id, payment_method_id, amount_cents, currency, status, idempotency_key, metadata, timestamps)
transactions (id, payment_intent_id, kind, status, amount_cents, processor_ref, failure_code, failure_message, timestamps)
ledger_entries (id, merchant_id, transaction_id, entry_type, amount_cents, currency, timestamps)
webhook_events (id, merchant_id, event_type, payload, signature, delivered_at, delivery_status, attempts, timestamps)
audit_logs (id, merchant_id, actor_type, actor_id, action, auditable_type, auditable_id, metadata, timestamps)
idempotency_records (id, merchant_id, idempotency_key, endpoint, request_hash, response_body, status_code, timestamps)
```

## Next Steps (Phase 2)

- Create controllers for all endpoints
- Implement routes
- Add request/response serializers
- Implement pagination
- Add comprehensive error handling
