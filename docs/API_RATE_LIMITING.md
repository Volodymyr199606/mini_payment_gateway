# API rate limiting (`/api/v1`)

Merchant-scoped throttling is enforced in **`Api::V1::BaseController`** via **`ApiRateLimitable`**, using **`RateLimiterService`** and **`Rails.cache`** (fixed time buckets).

## What is not throttled

- **`GET /api/v1/health`** — `HealthController` does not inherit `BaseController`; no API limiter.

## Categories and defaults

Limits are **max requests per window** (seconds). Defaults live in **`config/initializers/api_rate_limits.rb`** and can be overridden with `ENV` (see that file for names).

| Category | Typical routes | Scope |
|----------|----------------|--------|
| `payment_mutation` | `POST` create payment intent; `authorize`, `capture`, `void`; `POST` refunds | **Merchant** (`merchant_id` + category) |
| `read` | `GET` payment intents, customers | **Merchant** |
| `resource_write` | `POST` customers; `POST` payment methods | **Merchant** |
| `auth_account` | `GET /api/v1/merchants/me` | **Merchant** |
| `ai` | `POST /api/v1/ai/chat` | **Merchant** |
| `webhook_ingress` | `POST /api/v1/webhooks/processor` | **Client IP** (no API key) |
| `public_registration` | `POST /api/v1/merchants` (disabled; still throttled) | **Client IP** |
| `default` | Anything else under `BaseController` | **Merchant** |

## Behavior on limit

- **HTTP 429** `Too Many Requests`
- JSON: `error.code` = `rate_limited`, generic message, `details.retry_after_seconds` when available
- Headers: **`Retry-After`**, **`X-RateLimit-Limit`**, **`X-RateLimit-Remaining`** (0 when blocked; remaining on allowed responses)

## Metrics

`AbstractController` **skips `after_action` when a `before_action` halts**, so **`ApiRequestStat.record_request!` is invoked explicitly** when a merchant-scoped request is rate limited (so `rate_limited_count` and `requests_count` stay accurate). IP-only limits (webhooks, public merchant POST) do not have a merchant row.

## AI chat

The AI endpoint uses the **`ai`** category (default **20/min**, configurable via `API_RATE_LIMIT_AI` and `API_RATE_LIMIT_AI_WINDOW_SECONDS`). The dashboard AI UI keeps its **separate** cache keys and limits (`Dashboard::AiController`).

## Implementation notes

- Cache keys: `RateLimiterService.merchant_window_key` / `ip_window_key` + fixed window bucket suffix.
- **Do not** rely on raw-body hashing; limits are per category + scope only.
