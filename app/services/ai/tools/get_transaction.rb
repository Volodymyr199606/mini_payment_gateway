# frozen_string_literal: true

module Ai
  module Tools
    # Fetch transaction by id or processor_ref, scoped to merchant. Read-only.
    class GetTransaction < BaseTool
      def call
        return error('merchant_id required') unless merchant_id.present?

        txn = resolve_transaction
        return error(policy_error_message, code: 'access_denied') if txn.nil?
        return error(policy_error_message, code: 'access_denied') if policy_denied?(record: txn, record_type: 'transaction')

        ok(serialize(txn))
      rescue StandardError => e
        error(e.message, code: 'tool_error')
      end

      private

      def resolve_transaction
        tid = @args['transaction_id'].to_s.strip.presence&.to_i
        ref = @args['processor_ref'].to_s.strip.presence

        if tid.present?
          Transaction.joins(:payment_intent).where(payment_intents: { merchant_id: merchant_id }).find_by(id: tid)
        elsif ref.present?
          Transaction.joins(:payment_intent).where(payment_intents: { merchant_id: merchant_id }).find_by(processor_ref: ref)
        end
      end

      def serialize(txn)
        {
          id: txn.id,
          payment_intent_id: txn.payment_intent_id,
          kind: txn.kind,
          status: txn.status,
          amount_cents: txn.amount_cents,
          processor_ref: txn.processor_ref,
          created_at: txn.created_at.iso8601
        }
      end
    end
  end
end
