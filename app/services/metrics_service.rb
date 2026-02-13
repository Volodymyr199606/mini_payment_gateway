# frozen_string_literal: true

# Computes platform health metrics from DB. All metrics are derived at request time.
# No stateful counters, no external dependencies.
#
# Use MetricsService.compute(merchant: m) for merchant-scoped metrics.
class MetricsService
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
      # Financial KPIs (for dashboard consistency)
      captured_volume_cents: captured_volume_cents,
      refunded_cents: refunded_cents,
      net_cents: net_cents,
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

  def captured_volume_cents
    @merchant.payment_intents
             .joins(:transactions)
             .where(transactions: { kind: 'capture', status: 'succeeded' })
             .sum('transactions.amount_cents')
  end

  def refunded_cents
    # Refunds are stored negative; we return the magnitude (positive) for display.
    @merchant.ledger_entries.refunds.sum(:amount_cents).abs
  end

  # net_cents = charges − refunded_cents − fees (see docs/METRICS.md ledger sign conventions).
  def net_cents
    total_charges = @merchant.ledger_entries.charges.sum(:amount_cents)
    total_fees = @merchant.ledger_entries.fees.sum(:amount_cents)
    total_charges - refunded_cents - total_fees
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
