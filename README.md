# Mini Payment Gateway

A Rails 7+ API learning project that models real payment-platform concepts (Braintree-style).

## Tech Stack

- Rails 7.1+ (API + Dashboard)
- PostgreSQL
- bcrypt (for API key hashing)
- kaminari (for pagination)
- Hotwire (Turbo + Stimulus) for dashboard

## Setup

**Windows:** If `bundle` is not recognized, add Ruby to PATH first (new terminals need this each time, or add it in System Environment Variables):
   ```powershell
   $env:Path = "C:\Ruby40-x64\bin;" + $env:Path
   ```
   Use your actual Ruby install path if different (e.g. `C:\Ruby31-x64\bin`).

1. Install dependencies:
   ```bash
   bundle install
   ```

2. Set up database:
   ```bash
   rails db:create
   rails db:migrate
   rails db:seed
   ```
   
   Note: The seed script will output API keys for test merchants. Save them!

4. Start the server:
   ```bash
   rails server
   ```

5. (Optional) Configure webhook secret:
   ```bash
   export WEBHOOK_SECRET="your_secret_key_here"
   ```
   Note: A default secret is used in development if not set.

## API Endpoints

All endpoints are under `/api/v1` namespace. Most endpoints require `X-API-KEY` header.

### Health Check (No Auth Required)
- `GET /api/v1/health` - Returns `{status: "ok"}`

### Merchants
- `POST /api/v1/merchants` - Create merchant (returns API key)
- `GET /api/v1/merchants/me` - Get current merchant

### Customers
- `GET /api/v1/customers` - List customers (paginated)
- `POST /api/v1/customers` - Create customer
- `GET /api/v1/customers/:id` - Show customer

### Payment Methods
- `POST /api/v1/customers/:customer_id/payment_methods` - Create payment method

### Payment Intents
- `GET /api/v1/payment_intents` - List payment intents (paginated)
- `POST /api/v1/payment_intents` - Create payment intent
- `GET /api/v1/payment_intents/:id` - Show payment intent
- `POST /api/v1/payment_intents/:id/authorize` - Authorize payment
- `POST /api/v1/payment_intents/:id/capture` - Capture payment
- `POST /api/v1/payment_intents/:id/void` - Void payment

### Refunds
- `POST /api/v1/payment_intents/:payment_intent_id/refunds` - Create refund

### Webhooks
- `POST /api/v1/webhooks/processor` - Receive processor events (no auth required, signature verified)

## Dashboard

Visit `/dashboard` to access the merchant dashboard. Sign in with your API key to view:
- **Transactions**: Filterable list of all transactions
- **Payment Intent Details**: View complete payment intent information
- **Ledger**: Summary of charges, refunds, fees, and net volume

## Development Status

- ✅ Phase 0: Rails + Postgres setup, API skeleton, auth plumbing, health endpoint
- ✅ Phase 1: Models, migrations, associations, validations, seeds
- ✅ Phase 2: Controllers, routes, serializers, pagination, error handling
- ✅ Phase 3: Service objects, idempotency, ledger writes, state machine enforcement
- ✅ Phase 4: Webhooks + async delivery, signature verification, retry strategy
- ✅ Phase 5: Structured logging, rate limiting, audit logs, observability

## Seed Data

After running `rails db:seed`, you'll get:
- 2 test merchants with API keys (printed to console - save them!)
- Sample customers, payment methods, payment intents, transactions, and ledger entries

**⚠️ Important**: API keys are only shown once during seeding. Save them for testing API endpoints.
