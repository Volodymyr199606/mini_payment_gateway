# frozen_string_literal: true

module Ai
  module Contracts
    # Contract for intent resolution output (IntentResolver).
    # Stable keys: intent (ParsedIntent or hash), followup (hash).
    class IntentResolution
      attr_reader :intent, :followup, :contract_version

      def initialize(intent: nil, followup: {}, contract_version: nil)
        @intent = intent
        @followup = followup.is_a?(Hash) ? followup : {}
        @contract_version = contract_version || Contracts::INTENT_RESOLUTION_VERSION
      end

      def self.from_h(h)
        return nil if h.blank? || !h.is_a?(Hash)

        sym = h.with_indifferent_access
        intent = sym[:intent]
        intent = ParsedIntent.from_h(intent) if intent.is_a?(Hash)
        new(
          intent: intent,
          followup: sym[:followup].to_h,
          contract_version: sym[:contract_version].presence
        )
      end

      def to_h
        {
          intent: @intent.is_a?(ParsedIntent) ? @intent.to_h : @intent,
          followup: @followup,
          contract_version: @contract_version
        }.compact
      end
    end
  end
end
