# frozen_string_literal: true

module Ai
  module Agents
    # Answers "how much" / totals questions using real ledger data via Reporting::LedgerSummary.
    # LLM is used only to format the reply; numbers come from the tool only.
    class ReportingCalculationAgent < BaseAgent
      DISCLAIMER = 'Totals are based on ledger entries created on capture/refund (not authorize/void).'
      INFERRED_NOTE = "You didn't specify a range, so I used ALL TIME. Ask 'last 30 days' if you want a narrower window."

      def initialize(merchant_id:, message:, context_text: nil, citations: [])
        super(merchant_context: nil, message: message, context_text: context_text, citations: citations)
        @merchant_id = merchant_id
      end

      def call
        range_info = ::Ai::TimeRangeParser.extract_and_parse(@message)
        summary = ::Reporting::LedgerSummary.new(
          merchant_id: @merchant_id,
          from: range_info[:from],
          to: range_info[:to],
          currency: 'USD',
          group_by: 'none'
        ).call

        reply = format_reply(summary, range_info)
        {
          reply: reply,
          citations: @citations,
          data: summary,
          model_used: nil,
          fallback_used: false
        }
      end

      private

      def format_reply(summary, range_info)
        totals = summary[:totals]

        charges_s = AiMoneyHelper.format_cents(totals[:charges_cents])
        refunds_s = AiMoneyHelper.format_cents(totals[:refunds_cents])
        fees_s = AiMoneyHelper.format_cents(totals[:fees_cents])
        net_s = AiMoneyHelper.format_cents(totals[:net_cents])

        suffix = range_info[:inferred] ? ' (inferred)' : ''
        first_line = "Range: #{range_info[:range_label]}#{suffix}"
        inferred_note = range_info[:inferred] && range_info[:default_used] == 'all_time' ? "\n\n#{INFERRED_NOTE}" : ''
        entry_count = totals[:charges_cents].zero? && totals[:refunds_cents].zero? ? 'No' : (summary.dig(:counts, :captures_count).to_i + summary.dig(:counts, :refunds_count).to_i)

        <<~TEXT.strip
          #{first_line}

          For #{range_info[:from].strftime('%Y-%m-%d')} through #{range_info[:to].strftime('%Y-%m-%d')} (#{summary[:currency]}):
          • Charges: #{charges_s}
          • Refunds: #{refunds_s}
          • Fees: #{fees_s}
          • Net: #{net_s}
          (#{entry_count} ledger entries in range.)

          #{DISCLAIMER}#{inferred_note}
        TEXT
      end
    end
  end
end
