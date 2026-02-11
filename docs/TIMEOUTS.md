# Timeouts in Mini Payment Gateway

This document describes where timeouts are applied and how they interact with idempotency, retries, and database state.

## What Has Timeouts

| Component | What is limited | Config (ENV) | Default |
|----------|-----------------|--------------|---------|
| **Processor simulation** | Authorize, capture, void, refund “external” call | `PROCESSOR_TIMEOUT_SECONDS` | 3 |
| **Webhook delivery** | HTTP open + read to merchant webhook URL | `WEBHOOK_OPEN_TIMEOUT_SECONDS`, `WEBHOOK_READ_TIMEOUT_SECONDS` | 5, 10 |
| **Database** | Connection wait; per-statement execution | `DB_CONNECT_TIMEOUT_SECONDS`, `DB_STATEMENT_TIMEOUT_MS` | 5, 5000 |
| **Puma** | Worker lifetime (coarse request safety net) | `PUMA_WORKER_TIMEOUT_SECONDS` | 60 |

### Processor simulation (authorize / capture / void / refund)

- A hard limit is enforced with `Timeout.timeout(PROCESSOR_TIMEOUT_SECONDS)` around the simulated processor call only.
- If the limit is exceeded:
  - A **failed** transaction record is created with `failure_code: "timeout"` and `failure_message: "Processor request timed out"`.
  - For **authorize**: the payment intent is set to `failed`.
  - For **capture / void / refund**: the payment intent status is unchanged (no partial state).
- All DB writes for the operation are done inside a single `ActiveRecord::Base.transaction` so there are no partial writes on timeout.

### Webhook delivery

- Outbound HTTP to the merchant webhook URL uses:
  - `open_timeout`: time to establish the TCP connection (default 5s).
  - `read_timeout`: time to read the response body (default 10s).
- Timeouts (and other delivery failures) are handled by the existing retry/backoff logic: the event stays in a retryable state and `WebhookDeliveryJob` is rescheduled with exponential backoff until max attempts.

### Database

- **connect_timeout**: How long to wait when opening a new PostgreSQL connection. Helps avoid hanging when the DB host is unreachable.
- **statement_timeout**: Maximum time a single SQL statement can run (in milliseconds). Prevents one long-running query from blocking the app. Applied per connection via PostgreSQL session variables.

### Puma worker_timeout

- **Coarse-grained only**: The worker process is terminated after handling a request for longer than `PUMA_WORKER_TIMEOUT_SECONDS`. This is a safety net for runaway requests, not a precise per-request timeout.

## Idempotency and Retries

- **Processor timeouts**: The request fails and no successful response is stored for the idempotency key. A retry with the **same** idempotency key is a new request; the service runs again (and may succeed or timeout again). No duplicate successful transaction is created because the only stored outcome on timeout is a **failed** transaction.
- **Webhook timeouts**: Treated like any other delivery failure. The same webhook event is retried with backoff; idempotency for payment operations is unchanged.

## What Happens on Timeout

- **API response**: The client receives an error response (e.g. 422 or 500, depending on how the controller maps service errors). The response body includes the error message (e.g. “Processor request timed out” or “Authorization failed: …”).
- **DB state**:
  - **Authorize timeout**: Payment intent → `failed`; one **authorize** transaction with `status: 'failed'`, `failure_code: 'timeout'`.
  - **Capture / void / refund timeout**: Payment intent unchanged; one **capture** / **void** / **refund** transaction with `status: 'failed'`, `failure_code: 'timeout'`.
- **Logging**: Processor timeouts are logged as structured JSON with `event: 'processor_timeout'`, plus `request_id`, `merchant_id`, `payment_intent_id`, `transaction_id`, `transaction_kind`, and `timeout_seconds`.

## ENV reference

| Variable | Meaning | Default |
|----------|---------|---------|
| `PROCESSOR_TIMEOUT_SECONDS` | Max seconds for simulate processor (authorize/capture/void/refund) | 3 |
| `WEBHOOK_OPEN_TIMEOUT_SECONDS` | Webhook HTTP connection timeout (seconds) | 5 |
| `WEBHOOK_READ_TIMEOUT_SECONDS` | Webhook HTTP read timeout (seconds) | 10 |
| `DB_STATEMENT_TIMEOUT_MS` | PostgreSQL statement_timeout (milliseconds) | 5000 |
| `DB_CONNECT_TIMEOUT_SECONDS` | PostgreSQL connect timeout (seconds) | 5 |
| `PUMA_WORKER_TIMEOUT_SECONDS` | Puma worker timeout (seconds); coarse-grained | 60 |
