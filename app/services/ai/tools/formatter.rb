# frozen_string_literal: true

module Ai
  module Tools
    # Formats tool output for display. Deterministic, no LLM.
    class Formatter
      def self.format(tool_name, data)
        new(tool_name, data).format
      end

      def initialize(tool_name, data)
        @tool_name = tool_name
        @data = data
      end

      def format
        case @tool_name
        when 'get_ledger_summary' then format_ledger_summary
        when 'get_payment_intent' then format_payment_intent
        when 'get_transaction' then format_transaction
        when 'get_webhook_event' then format_webhook_event
        when 'get_merchant_account' then format_merchant_account
        else data_summary
        end
      end

      private

      def format_ledger_summary
        t = @data[:totals] || {}
        c = @data[:counts] || {}
        from = @data[:from]
        to = @data[:to]

        charges = (t[:charges_cents] || 0) / 100.0
        refunds = (t[:refunds_cents] || 0) / 100.0
        fees = (t[:fees_cents] || 0) / 100.0
        net = (t[:net_cents] || 0) / 100.0

        lines = [
          "Range: #{from} to #{to}",
          "• Charges: #{format_money(charges)}",
          "• Refunds: #{format_money(refunds)}",
          "• Fees: #{format_money(fees)}",
          "• Net: #{format_money(net)}",
          "(#{c[:captures_count].to_i + c[:refunds_count].to_i} ledger entries in range.)"
        ]
        lines.join("\n")
      end

      def format_payment_intent
        pi = @data
        "Payment Intent ##{pi[:id]}: #{format_money(pi[:amount_cents] / 100.0)} #{pi[:currency]} | status: #{pi[:status]} | dispute: #{pi[:dispute_status]}"
      end

      def format_transaction
        txn = @data
        "Transaction ##{txn[:id]} (#{txn[:kind]}): #{format_money(txn[:amount_cents] / 100.0)} | status: #{txn[:status]} | ref: #{txn[:processor_ref]}"
      end

      def format_webhook_event
        evt = @data
        "Webhook Event ##{evt[:id]}: #{evt[:event_type]} | delivery: #{evt[:delivery_status]} | attempts: #{evt[:attempts]}"
      end

      def format_merchant_account
        m = @data
        lines = [
          "Account: #{m[:name]} (##{m[:id]})",
          "Status: #{m[:status]}",
          "Payment intents: #{m[:payment_intents_count]}",
          "Webhook events: #{m[:webhook_events_count]}"
        ]
        lines.join("\n")
      end

      def format_money(amount)
        Kernel.format('$%.2f', amount)
      end

      def data_summary
        @data.to_json
      end
    end
  end
end
