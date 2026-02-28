# frozen_string_literal: true

# Computes platform health metrics from DB. All metrics are derived at request time.
# No stateful counters, no external dependencies.
#
# Use MetricsService.compute(merchant: m) for merchant-scoped metrics.
# Financial KPIs (captured_volume, refunded, net) use LedgerEntry as single source of truth via Reporting::LedgerSummary.
class MetricsService
  # All-time range for financial KPIs (matches dashboard cards and reporting agent default).
  ALL_TIME_FROM = Time.zone.parse('2000-01-01 00:00:00')

  def self.compute(merchant:)
    new(merchant: merchant).compute
  end

  def initialize(merchant:)
    @merchant = merchant
  end

  def compute
    {
      payment_intents_created: payment_intents_created,
      transactions_authorized: transactions_authorized,
      transactions_captured: transactions_captured,
      transactions_refunded: transactions_refunded,
      webhook_events_received: webhook_events_received,
      webhook_delivery_failures: webhook_delivery_failures,
      # Financial KPIs (LedgerEntry single source of truth, all-time)
      captured_volume_cents: ledger_totals[:charges_cents],
      refunded_cents: ledger_totals[:refunds_cents],
      net_cents: ledger_totals[:net_cents],
      # API Health (last 24h, merchant-scoped)
      api_requests_total: api_requests_total_24h,
      api_errors_total: api_errors_total_24h,
      api_rate_limited_total: api_rate_limited_total_24h
    }
  end

  def payment_intents_created
    @merchant.payment_intents.count
  end

  def transactions_authorized
    @merchant.transactions.authorize.count
  end

  def transactions_captured
    @merchant.transactions.capture.count
  end

  def transactions_refunded
    @merchant.transactions.refund.count
  end

  def webhook_events_received
    @merchant.webhook_events.count
  end

  def webhook_delivery_failures
    @merchant.webhook_events.failed.count
  end

  # All-time totals from LedgerEntry via Reporting::LedgerSummary.
  def ledger_totals
    @ledger_totals ||= begin
      result = Reporting::LedgerSummary.new(
        merchant_id: @merchant.id,
        from: ALL_TIME_FROM,
        to: Time.current,
        currency: 'USD',
        group_by: 'none'
      ).call
      result[:totals]
    end
  end

  # API request stats: sum of daily counters for recent activity (1–2 calendar days; see docs/METRICS.md).
  def api_requests_total_24h
    @merchant.api_request_stats.where('date >= ?', (Time.current.utc - 24.hours).to_date).sum(:requests_count)
  end

  # Server errors only: HTTP 5xx. Client errors (4xx except 429) are not tracked.
  def api_errors_total_24h
    @merchant.api_request_stats.where('date >= ?', (Time.current.utc - 24.hours).to_date).sum(:errors_count)
  end

  # HTTP 429 responses only; tracked separately from other 4xx.
  def api_rate_limited_total_24h
    @merchant.api_request_stats.where('date >= ?', (Time.current.utc - 24.hours).to_date).sum(:rate_limited_count)
  end
end
