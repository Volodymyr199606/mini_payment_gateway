# frozen_string_literal: true

module Reporting
  # Deterministic ledger totals for a merchant over a time range.
  # Sign convention: LedgerEntry stores charge (positive), refund (negative), fee (+/-).
  # Output: charges_cents and refunds_cents are positive numbers; net_cents = charges - refunds + fees (signed).
  class LedgerSummary
    DEFAULT_CURRENCY = 'USD'

    def initialize(merchant_id:, from:, to:, currency: nil, group_by: 'none')
      @merchant_id = merchant_id
      @from = from.is_a?(String) ? Time.zone.parse(from) : from
      @to = to.is_a?(String) ? Time.zone.parse(to) : to
      @currency = (currency || DEFAULT_CURRENCY).to_s.upcase
      @group_by = group_by.to_s.downcase
    end

    def call
      base = LedgerEntry.where(merchant_id: @merchant_id)
                       .where(created_at: @from..@to)
                       .where(currency: @currency)

      charges_cents = base.charges.sum(:amount_cents)
      refunds_sum_cents = base.refunds.sum(:amount_cents) # negative in DB
      fees_cents = base.fees.sum(:amount_cents)

      # Output refunds as positive number for display. Net = charges - refunds - fees (fees signed: positive = merchant pays).
      refunds_cents_display = refunds_sum_cents.abs
      net_cents = charges_cents - refunds_cents_display - fees_cents

      captures_count = base.charges.count
      refunds_count = base.refunds.count

      result = {
        currency: @currency,
        from: @from.iso8601,
        to: @to.iso8601,
        totals: {
          charges_cents: charges_cents,
          refunds_cents: refunds_cents_display,
          fees_cents: fees_cents,
          net_cents: net_cents
        },
        counts: {
          captures_count: captures_count,
          refunds_count: refunds_count
        }
      }

      if @group_by != 'none' && %w[day week month].include?(@group_by)
        result[:breakdown] = breakdown(base)
      end

      result
    end

    private

    def breakdown(base)
      # PostgreSQL: date_trunc on timestamp
      group_sql = case @group_by
                  when 'day' then "date_trunc('day', ledger_entries.created_at)"
                  when 'week' then "date_trunc('week', ledger_entries.created_at)"
                  when 'month' then "date_trunc('month', ledger_entries.created_at)"
                  else return []
                  end

      rows = base.group(group_sql)
                 .select(
                   "#{group_sql} AS period",
                   "SUM(CASE WHEN entry_type = 'charge' THEN amount_cents ELSE 0 END) AS charges_cents",
                   "SUM(CASE WHEN entry_type = 'refund' THEN amount_cents ELSE 0 END) AS refunds_cents_raw",
                   "SUM(CASE WHEN entry_type = 'fee' THEN amount_cents ELSE 0 END) AS fees_cents"
                 )
                 .order('period')

      rows.map do |row|
        {
          period: row.period.to_s,
          charges_cents: row.charges_cents.to_i,
          refunds_cents: row.refunds_cents_raw.to_i.abs,
          fees_cents: row.fees_cents.to_i,
          net_cents: row.charges_cents.to_i - row.refunds_cents_raw.to_i.abs - row.fees_cents.to_i
        }
      end
    end
  end
end
