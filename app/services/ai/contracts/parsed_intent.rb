# frozen_string_literal: true

module Ai
  module Contracts
    # Contract for parsed tool intent (IntentDetector output).
    # Stable keys: tool_name, args.
    class ParsedIntent
      attr_reader :tool_name, :args, :contract_version

      def initialize(tool_name:, args: {}, contract_version: nil)
        @tool_name = tool_name.to_s.strip.presence
        @args = args.is_a?(Hash) ? args.to_h : {}
        @contract_version = contract_version || Contracts::PARSED_INTENT_VERSION
      end

      def self.from_h(h)
        return nil if h.blank? || !h.is_a?(Hash)

        sym = h.with_indifferent_access
        args = (sym[:args].to_h || {}).transform_keys(&:to_sym)
        new(
          tool_name: sym[:tool_name].to_s,
          args: args,
          contract_version: sym[:contract_version].presence
        )
      end

      def present?
        @tool_name.present?
      end

      def to_h
        {
          tool_name: @tool_name,
          args: @args,
          contract_version: @contract_version
        }.compact
      end

      def validate!
        return true unless Rails.env.development? || Rails.env.test?
        raise ArgumentError, 'ParsedIntent: tool_name required' if @tool_name.blank?
        true
      end
    end
  end
end
