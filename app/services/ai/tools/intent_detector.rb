# frozen_string_literal: true

module Ai
  module Tools
    # Detects obvious tool intents from message. Returns { tool_name:, args: } or nil.
    # Constrained patterns only. Max one intent per message.
    class IntentDetector
      PI_PATTERN = /\b(?:payment[_\s]?intent|pi)[\s#:]*(?:id)?[\s]*(\d+)/i
      TXN_ID_PATTERN = /\b(?:transaction|txn)[\s#:]*(?:id\s*)?(\d+)/i
      TXN_REF_PATTERN = /\b(txn_[a-zA-Z0-9]+)\b/
      WEBHOOK_PATTERN = /\b(?:webhook[_\s]?event|webhook\s+event)[\s#:]*(?:id)?[\s]*(\d+)/i
      ACCOUNT_PATTERN = /\b(?:my\s+)?(?:account|merchant)\s*(?:info|summary|details)?\b/i

      # Explicit phrases only — %w splits on spaces, so never use %w for multi-word keys (that reintroduces bare "how").
      LEDGER_PHRASE_SUBSTRINGS = [
        'last 7 days', 'last week', 'last month', 'all time',
        'total charges', 'total refunds', 'net volume', 'net balance', 'how much'
      ].freeze

      def self.detect(message)
        new(message).detect
      end

      def initialize(message)
        @msg = message.to_s.strip.downcase
      end

      def detect
        # Order matters: most specific first
        return detect_payment_intent if match = @msg.match(PI_PATTERN)
        return detect_transaction if @msg.match(TXN_ID_PATTERN) || @msg.match(TXN_REF_PATTERN)
        return detect_webhook_event if @msg.match(WEBHOOK_PATTERN)
        return detect_account if @msg.match(ACCOUNT_PATTERN)
        return detect_ledger_summary if ledger_intent?

        nil
      end

      private

      def ledger_intent?
        return true if LEDGER_PHRASE_SUBSTRINGS.any? { |p| @msg.include?(p) }

        return true if @msg.match?(/\b(today|yesterday)\b/)
        return true if @msg.match?(/\btotals\b/)
        return true if @msg.match?(/\bhow\s+much\b/)

        # Reporting-ish: money movement keywords + scope words — exclude obvious docs/policy questions
        if @msg.match?(/\b(refunds?|charges?|ledger|net)\b/) &&
           @msg.match?(/\b(what|show|give|my|last|this|week|month|days|volume|balance|money|sales|revenue|summary|amount|is)\b/) &&
           !@msg.match?(/\b(policy|policies|terms|legal|documentation|docs?|compliance|pci)\b/)
          return true
        end

        false
      end

      def detect_payment_intent
        m = @msg.match(PI_PATTERN)
        return nil unless m

        { tool_name: 'get_payment_intent', args: { payment_intent_id: m[1].to_i } }
      end

      def detect_transaction
        m = @msg.match(TXN_REF_PATTERN)
        if m
          return { tool_name: 'get_transaction', args: { processor_ref: m[1] } }
        end

        m = @msg.match(TXN_ID_PATTERN)
        return nil unless m

        { tool_name: 'get_transaction', args: { transaction_id: m[1].to_i } }
      end

      def detect_webhook_event
        m = @msg.match(WEBHOOK_PATTERN)
        return nil unless m

        { tool_name: 'get_webhook_event', args: { webhook_event_id: m[1].to_i } }
      end

      def detect_account
        { tool_name: 'get_merchant_account', args: {} }
      end

      def detect_ledger_summary
        range_info = ::Ai::TimeRangeParser.extract_and_parse(@msg)
        {
          tool_name: 'get_ledger_summary',
          args: {
            from: range_info[:from].iso8601,
            to: range_info[:to].iso8601
          }
        }
      rescue ::Ai::TimeRangeParser::ParseError
        { tool_name: 'get_ledger_summary', args: { preset: 'all_time' } }
      end
    end
  end
end
