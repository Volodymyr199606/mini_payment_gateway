# frozen_string_literal: true

module Dashboard
  class OverviewController < Dashboard::BaseController
    def index
      # KPI: captured volume (sum of successful capture transaction amounts)
      captured_cents = current_merchant.payment_intents
                                       .joins(:transactions)
                                       .where(transactions: { kind: 'capture', status: 'succeeded' })
                                       .sum('transactions.amount_cents')
      @captured_volume_cents = captured_cents

      # KPI: refunded (from ledger refunds)
      @refunded_cents = current_merchant.ledger_entries.refunds.sum(:amount_cents).abs

      # KPI: net (charges - refunds - fees)
      @total_charges_cents = current_merchant.ledger_entries.charges.sum(:amount_cents)
      @total_fees_cents = current_merchant.ledger_entries.fees.sum(:amount_cents)
      @net_cents = @total_charges_cents - @refunded_cents - @total_fees_cents

      # KPI: failed webhooks
      @failed_webhooks_count = current_merchant.webhook_events.failed.count
    end
  end
end
