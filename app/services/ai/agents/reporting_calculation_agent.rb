# frozen_string_literal: true

module Ai
  module Agents
    # Answers "how much" / totals questions using real ledger data via Reporting::LedgerSummary.
    # LLM is used only to format the reply; numbers come from the tool only.
    class ReportingCalculationAgent < BaseAgent
      DEFAULT_RANGE = 'last 7 days'
      DISCLAIMER = 'Totals are based on ledger entries created on capture/refund (not authorize/void).'

      def initialize(merchant_id:, message:, context_text: nil, citations: [])
        super(merchant_context: nil, message: message, context_text: context_text, citations: citations)
        @merchant_id = merchant_id
      end

      def call
        from_time, to_time = parse_time_range
        summary = ::Reporting::LedgerSummary.new(
          merchant_id: @merchant_id,
          from: from_time,
          to: to_time,
          currency: 'USD',
          group_by: 'none'
        ).call

        reply = format_reply(summary, from_time, to_time)
        {
          reply: reply,
          citations: @citations,
          data: summary,
          model_used: nil,
          fallback_used: false
        }
      end

      private

      def parse_time_range
        phrase = detect_time_phrase
        ::Ai::TimeRangeParser.parse(phrase)
      rescue ::Ai::TimeRangeParser::ParseError
        # Fallback to default range (max 365 days is enforced in parser)
        ::Ai::TimeRangeParser.parse(DEFAULT_RANGE)
      end

      def detect_time_phrase
        msg = @message.downcase
        ::Ai::TimeRangeParser::PHRASES.each_key do |phrase|
          return phrase if msg.include?(phrase)
        end
        DEFAULT_RANGE
      end

      def format_reply(summary, from_time, to_time)
        totals = summary[:totals]
        from_s = from_time.strftime('%Y-%m-%d')
        to_s = to_time.strftime('%Y-%m-%d')

        charges_s = AiMoneyHelper.format_cents(totals[:charges_cents])
        refunds_s = AiMoneyHelper.format_cents(totals[:refunds_cents])
        fees_s = AiMoneyHelper.format_cents(totals[:fees_cents])
        net_s = AiMoneyHelper.format_cents(totals[:net_cents])

        <<~TEXT.strip
          For #{from_s} through #{to_s} (#{summary[:currency]}):
          • Charges: #{charges_s}
          • Refunds: #{refunds_s}
          • Fees: #{fees_s}
          • Net: #{net_s}
          (#{totals[:charges_cents].zero? && totals[:refunds_cents].zero? ? 'No' : summary.dig(:counts, :captures_count).to_i + summary.dig(:counts, :refunds_count).to_i} ledger entries in range.)

          #{DISCLAIMER}
        TEXT
      end
    end
  end
end
