# frozen_string_literal: true

module Ai
  module Tools
    # Fetch current merchant account summary. Read-only.
    class GetMerchantAccount < BaseTool
      def call
        return error('merchant_id required') unless merchant_id.present?
        return error(policy_error_message, code: 'access_denied') unless merchant
        return error(policy_error_message, code: 'access_denied') if policy_denied?(record: merchant, record_type: 'merchant')

        ok(serialize)
      rescue StandardError => e
        error(e.message, code: 'tool_error')
      end

      private

      def serialize
        {
          id: merchant.id,
          name: merchant.name,
          status: merchant.status,
          email: merchant.email,
          payment_intents_count: merchant.payment_intents.count,
          webhook_events_count: merchant.webhook_events.count
        }
      end
    end
  end
end
