# Metrics in Mini Payment Gateway

This document describes the metrics exposed by the platform, why they matter, and what they do not cover.

## What Metrics Exist

All metrics are computed at request time from the database. No external monitoring tools, background jobs, or in-memory counters are used.

| Metric | Description | Source |
|--------|-------------|--------|
| **payment_intents_created** | Total payment intents created for the merchant | `payment_intents.count` |
| **transactions_authorized** | Count of authorize transactions | `transactions.where(kind: 'authorize').count` |
| **transactions_captured** | Count of capture transactions | `transactions.where(kind: 'capture').count` |
| **transactions_refunded** | Count of refund transactions | `transactions.where(kind: 'refund').count` |
| **webhook_events_received** | Total webhook events ingested | `webhook_events.count` |
| **webhook_delivery_failures** | Webhook events that failed delivery after retries | `webhook_events.where(delivery_status: 'failed').count` |
| **captured_volume_cents** | Sum of successful capture amounts (financial KPI) | `transactions` joined with `payment_intents` |
| **refunded_cents** | Sum of refunded amounts (financial KPI) | `ledger_entries.refunds` |
| **net_cents** | Charges minus refunds minus fees (financial KPI) | `ledger_entries` |
| **api_requests_total** | API requests (recent daily counters; merchant-scoped) | `api_request_stats` (persisted daily counters) |
| **api_errors_total** | HTTP 5xx only (server errors) | `api_request_stats.errors_count` |
| **api_rate_limited_total** | HTTP 429 only (rate limited) | `api_request_stats.rate_limited_count` |

## Ledger sign conventions

Financial metrics (`refunded_cents`, `net_cents`, and dashboard totals) are derived from `LedgerEntry`. The following conventions define how `amount_cents` is stored and how we aggregate.

### LedgerEntry.amount_cents by entry_type

- **charge**: Stored **positive**. Represents money charged (e.g. authorization or capture). Sum of charges = total revenue from the ledger.
- **refund**: Stored **negative**. Represents money returned to the customer. The app creates refund entries with `amount_cents: -refund_amount`. When we display “refunded” we use the magnitude: `refunds.sum(:amount_cents).abs`.
- **fee**: Stored **positive** when the merchant pays (e.g. processing fee), **negative** when the merchant receives (e.g. rebate). Sum of fees can be positive or negative.

### Net cents formula

`net_cents` is defined as:

- **net_cents = total_charges − refunded_cents − total_fees**

Where:

- **total_charges** = `ledger_entries.charges.sum(:amount_cents)` (positive).
- **refunded_cents** = `ledger_entries.refunds.sum(:amount_cents).abs` (positive magnitude of refunds; refunds are stored negative in the DB).
- **total_fees** = `ledger_entries.fees.sum(:amount_cents)` (positive when merchant pays, negative when merchant receives). Subtracting this in the formula means: positive fees reduce net, negative fees increase net.

No ledger math or stored data is changed by metrics; we only read and aggregate existing rows.

### Example

- Captured: $100.00 → one charge entry with `amount_cents: 10000`.
- Refunded: $25.00 → one refund entry with `amount_cents: -2500`.
- Fee: $3.00 (merchant pays) → one fee entry with `amount_cents: 300`.

Then:

- total_charges = 10000  
- refunded_cents = 2500  
- total_fees = 300  
- **net_cents = 10000 − 2500 − 300 = 7200** ($72.00).

## API Request Metrics (Approach B: Persisted Daily Counters)

API health metrics are stored in `api_request_stats`: one row per merchant per calendar day, with `requests_count`, `errors_count`, and `rate_limited_count`. Each authenticated API request triggers an atomic upsert that increments today’s counters.

### Error classification

- **Server errors (api_errors_total)**: Only HTTP 5xx responses are counted. These indicate server-side failures.
- **Client errors**: HTTP 4xx (except 429) are not tracked. Bad request, unauthorized, not found, validation errors, etc. do not increment any error counter.
- **Rate limiting (api_rate_limited_total)**: Only HTTP 429 is counted. It is tracked separately so it is not mixed with server errors.

### Daily aggregation window

The dashboard sums rows where `date >= (now - 24h).to_date`. Because we use calendar-day buckets, this can include **up to two calendar days** (e.g. today and yesterday). The value is an approximation of recent activity, not a strict 24-hour sliding window. The UI label “API Health (daily counters)” reflects this.

- **Why they are in the dashboard**: To give merchants a quick view of API usage and stability (request volume, server errors, rate limiting) without adding monitoring gems or external systems.
- **Scope**: Only authenticated API requests are counted. Webhook receiver and other unauthenticated endpoints do not update these stats. Stats updates are best-effort; failures are swallowed so they never affect API responses.

## Where Metrics Are Exposed

- **Dashboard Overview** (`/dashboard`): Metrics are shown in the Overview page when a merchant is signed in. All counts are scoped to the current merchant.

## Why Each Metric Matters (Payments Context)

- **payment_intents_created**: Indicates checkout funnel volume. A drop may signal integration or API issues.
- **transactions_authorized**: Authorization volume. Compare to captures to see abandoned authorizations.
- **transactions_captured**: Successful settlements. Core revenue metric.
- **transactions_refunded**: Refund volume. Spikes may indicate disputes or customer satisfaction issues.
- **webhook_events_received**: Inbound event volume from the processor. Confirms webhook ingestion is working.
- **webhook_delivery_failures**: Failed outbound deliveries. High counts mean merchants may miss critical events (e.g. chargebacks, failures).
- **api_requests_total**: Total authenticated API request volume (recent daily counters). Helps confirm traffic and integration health.
- **api_errors_total**: HTTP 5xx count only. Spikes indicate server-side issues. Client errors (4xx except 429) are not included.
- **api_rate_limited_total**: HTTP 429 count only. Indicates when rate limits are being hit; tracked separately from server errors.

## What These Metrics Do NOT Cover

- **Latency histograms**: No request timing or percentiles (p50, p95, p99). Intentionally excluded; would require middleware and aggregation.
- **Infrastructure metrics**: CPU, memory, disk, network. Use host/container monitoring instead.
- **Error rates by endpoint**: No per-route success/failure breakdown.
- **Real-time dashboards**: Metrics are computed on page load, not streamed or polled.
- **Alerts or SLOs**: No alerting, thresholds, or SLO definitions.
- **Distributed tracing**: No request tracing across services; intentionally excluded.

## Implementation

Metrics are computed by `MetricsService` (`app/services/metrics_service.rb`). The service uses standard ActiveRecord queries and existing indexes. Controllers call `MetricsService.compute(merchant: current_merchant)` and pass the result to the view.

API request metrics use the `ApiRequestStat` model and a daily table keyed by `(merchant_id, date)`. An `after_action` in `Api::V1::BaseController` calls `ApiRequestStat.record_request!` for each authenticated API request with `is_error: response.status >= 500` and `is_rate_limited: response.status == 429`; the method uses a single SQL upsert so increments are atomic. If the update fails, the error is swallowed so API responses are never affected.

## Reversibility

To remove metrics:

1. Delete `app/services/metrics_service.rb`.
2. Restore the Overview controller to compute financial KPIs inline (or keep a minimal version).
3. Remove the Platform Metrics and API Health sections from the Overview view.
4. Remove `has_many :transactions, through: :payment_intents` from `Merchant` if no longer needed elsewhere.
5. To remove API request metrics: drop the `after_action :record_api_request_stat` from `Api::V1::BaseController`, remove `ApiRequestStat` and `has_many :api_request_stats` from `Merchant`, and run a migration to drop `api_request_stats`.
