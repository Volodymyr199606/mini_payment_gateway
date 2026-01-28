# Phase 0: Rails + Postgres Setup Complete

## Commands to Run

```bash
# 1. Install dependencies
bundle install

# 2. Create and setup database
rails db:create
rails db:migrate

# 3. Start the server
rails server
```

## Test the Health Endpoint

```bash
# No authentication required
curl http://localhost:3000/api/v1/health

# Expected response:
# {"status":"ok"}
```

## Files Created/Modified

### Core Configuration
- `Gemfile` - Rails 7.1, PostgreSQL, bcrypt, bootsnap, RSpec
- `config/application.rb` - API-only mode, UTC timezone
- `config/database.yml` - PostgreSQL configuration
- `config/routes.rb` - `/api/v1` namespace with health endpoint
- `config/puma.rb` - Server configuration
- `config/environments/*.rb` - Development, test, production configs

### Authentication Plumbing
- `app/controllers/concerns/api_authenticatable.rb` - API key authentication concern
  - Reads `X-API-KEY` header
  - Will be fully implemented in Phase 1 with Merchant model
  - Provides `render_error` helper for consistent error responses

### Controllers
- `app/controllers/api/v1/base_controller.rb` - Base API controller
  - Includes `ApiAuthenticatable` (requires auth for all endpoints)
  - Global error handling
- `app/controllers/api/v1/health_controller.rb` - Health check endpoint
  - No authentication required
  - Returns `{status: "ok"}`

### Supporting Files
- `app/models/application_record.rb` - Base model class
- `app/jobs/application_job.rb` - Base job class
- `app/mailers/application_mailer.rb` - Base mailer class
- `config/initializers/cors.rb` - CORS configuration
- `config/initializers/filter_parameter_logging.rb` - Security logging
- `.gitignore` - Standard Rails ignores

## Architecture Notes

1. **API-Only Mode**: Rails configured for JSON-only responses
2. **Authentication**: Concern-based auth ready for Phase 1 Merchant model
3. **Error Handling**: Consistent error response format:
   ```json
   {
     "error": {
       "code": "error_code",
       "message": "Human readable message",
       "details": {}
     }
   }
   ```
4. **Namespace**: All endpoints under `/api/v1`
5. **Base Controller**: All authenticated endpoints will inherit from `Api::V1::BaseController`

## Next Steps (Phase 1)

- Create Merchant, Customer, PaymentMethod, PaymentIntent, Transaction, LedgerEntry, WebhookEvent, AuditLog models
- Implement migrations with proper associations
- Add validations
- Create seed data
- Complete API key authentication in `ApiAuthenticatable`
