# frozen_string_literal: true

module Ai
  module Tools
    # Base for deterministic tools. Read-only, no side effects.
    class BaseTool
      def initialize(args:, context:)
        @args = args.to_h.transform_keys(&:to_s)
        @context = context.to_h.transform_keys(&:to_s)
      end

      def call
        raise NotImplementedError
      end

      protected

      def merchant_id
        @context['merchant_id']&.to_i
      end

      def merchant
        return nil unless merchant_id.present?

        @merchant ||= Merchant.find_by(id: merchant_id)
      end

      def error(message, code: 'validation_error')
        { success: false, error: message, error_code: code }
      end

      def policy
        @policy ||= ::Ai::Policy::Authorization.call(context: @context)
      end

      def policy_denied?(record:, record_type: nil)
        decision = policy.allow_record?(record: record, record_type: record_type)
        return false if decision.allowed?
        @last_policy_decision = decision
        true
      end

      def policy_error_message
        ::Ai::Policy::Authorization.denied_message
      end

      def ok(data)
        { success: true, data: data }
      end
    end
  end
end
