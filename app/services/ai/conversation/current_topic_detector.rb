# frozen_string_literal: true

module Ai
  module Conversation
    # Lightweight rule-based detection of current conversation topic from recent messages.
    # Used for memory metadata and summarization triggers; no LLM calls.
    class CurrentTopicDetector
      # Keyword patterns for payment gateway topics (lowercase)
      TOPIC_PATTERNS = {
        refund_flow: [/refund/, /void/, /reversal/, /chargeback/],
        webhooks: [/webhook/, /event.*notif/, /callback.*url/, /signature.*valid/],
        auth_capture: [/authorize/, /auth.*capture/, /capture/, /hold/, /settle/],
        ledger_reporting: [/ledger/, /report/, /reconcil/, /export/, /statement/],
        merchant_dashboard: [/dashboard/, /merchant.*portal/, /login/, /account.*setting/],
        onboarding_api_keys: [/onboard/, /api.?key/, /integration/, /setup/, /get.?started/]
      }.freeze

      def self.call(recent_messages)
        new(recent_messages).call
      end

      def initialize(recent_messages)
        @messages = Array(recent_messages).map { |m| m[:content].to_s + ' ' + m[:role].to_s }
        @combined = @messages.join(' ').downcase
      end

      def call
        return nil if @combined.blank?

        scores = {}
        TOPIC_PATTERNS.each do |topic, patterns|
          scores[topic] = patterns.sum { |re| @combined.scan(re).size }
        end

        best = scores.max_by { |_, count| count }
        best && best[1] > 0 ? best[0].to_s.tr('_', ' ') : nil
      end
    end
  end
end
