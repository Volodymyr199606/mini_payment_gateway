# frozen_string_literal: true

module Ai
  module Replay
    # Builds safe replay input from a historical ai_request_audit.
    # Only uses persisted metadata; no raw messages or secrets.
    # When original was tool path, reconstructs resolved_intent + synthetic message.
    class ReplayInputBuilder
      attr_reader :audit, :replay_possible, :reason_code, :message, :resolved_intent, :merchant_id

      def self.call(audit)
        new(audit).call
      end

      def initialize(audit)
        @audit = audit
        @replay_possible = false
        @reason_code = nil
        @message = nil
        @resolved_intent = nil
        @merchant_id = audit.merchant_id
      end

      def call
        return self unless @merchant_id.present?
        return mark_impossible('no_tool_usage') unless audit.tool_used? && Array(audit.tool_names).any?

        tool_name = Array(audit.tool_names).first.to_s
        args = build_args_from_audit(tool_name)
        @resolved_intent = { tool_name: tool_name, args: args }
        @message = synthetic_message(tool_name, args)
        @replay_possible = true
        @reason_code = 'intent_replay'
        self
      end

      def possible?
        @replay_possible
      end

      private

      def mark_impossible(code)
        @reason_code = code
        self
      end

      def build_args_from_audit(tool_name)
        entities = audit.parsed_entities || {}
        hints = audit.parsed_intent_hints || {}
        ids = (entities.is_a?(Hash) ? entities['ids'] || entities[:ids] : {}).to_h

        case tool_name
        when 'get_payment_intent'
          pid = ids['payment_intent_id'] || ids[:payment_intent_id]
          pid ? { payment_intent_id: pid.to_i } : {}
        when 'get_transaction'
          tid = ids['transaction_id'] || ids[:transaction_id]
          ref = ids['processor_ref'] || ids[:processor_ref]
          return { processor_ref: ref.to_s } if ref.present?
          tid ? { transaction_id: tid.to_i } : {}
        when 'get_webhook_event'
          wid = ids['webhook_event_id'] || ids[:webhook_event_id]
          wid ? { webhook_event_id: wid.to_i } : {}
        when 'get_merchant_account'
          {}
        when 'get_ledger_summary'
          from = hints['from'] || hints[:from]
          to = hints['to'] || hints[:to]
          return { from: from.to_s, to: to.to_s } if from.present? && to.present?
          { preset: 'all_time' }
        else
          {}
        end
      end

      def synthetic_message(tool_name, args)
        case tool_name
        when 'get_payment_intent'
          pid = args[:payment_intent_id] || args['payment_intent_id']
          pid ? "payment intent #{pid}" : "payment intent"
        when 'get_transaction'
          ref = args[:processor_ref] || args['processor_ref']
          return "txn #{ref}" if ref.present?
          tid = args[:transaction_id] || args['transaction_id']
          tid ? "transaction #{tid}" : "transaction"
        when 'get_webhook_event'
          wid = args[:webhook_event_id] || args['webhook_event_id']
          wid ? "webhook event #{wid}" : "webhook event"
        when 'get_merchant_account'
          'my account info'
        when 'get_ledger_summary'
          'last 7 days'
        else
          "replay #{tool_name}"
        end
      end
    end
  end
end
