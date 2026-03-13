# frozen_string_literal: true

module Ai
  module Tools
    # Fetch payment intent by id, scoped to merchant. Read-only.
    class GetPaymentIntent < BaseTool
      def call
        return error('merchant_id required') unless merchant_id.present?
        return error('payment_intent_id required') unless id.present?

        pi = merchant.payment_intents.find_by(id: id)
        return error(policy_error_message, code: 'access_denied') if pi.nil?
        return error(policy_error_message, code: 'access_denied') if policy_denied?(record: pi, record_type: 'payment_intent')

        ok(serialize(pi))
      rescue StandardError => e
        error(e.message, code: 'tool_error')
      end

      private

      def id
        @id ||= @args['payment_intent_id'].to_s.strip.presence&.to_i
      end

      def serialize(pi)
        {
          id: pi.id,
          merchant_id: pi.merchant_id,
          amount_cents: pi.amount_cents,
          currency: pi.currency,
          status: pi.status,
          dispute_status: pi.dispute_status,
          created_at: pi.created_at.iso8601
        }
      end
    end
  end
end
