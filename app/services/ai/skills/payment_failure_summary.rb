# frozen_string_literal: true

module Ai
  module Skills
    # Summarizes payment/transaction failure situation. Uses deterministic data.
    # Reuses Explanations::Renderer where applicable; factual and domain-specific.
    class PaymentFailureSummary < BaseSkill
      DEFINITION = SkillDefinition.new(
        key: :payment_failure_summary,
        class_name: 'Ai::Skills::PaymentFailureSummary',
        description: 'Summarize what failed and where in the payment lifecycle.',
        deterministic: true,
        dependencies: %i[tools context],
        input_contract: 'payment_intent or transaction hash with failed/non-success state, merchant_id',
        output_contract: 'SkillResult with failure summary, lifecycle position, suggested meaning'
      )

      def execute(context:)
        merchant_id = context[:merchant_id].to_i
        return missing_context unless merchant_id.positive?

        pi = extract_entity(context, :payment_intent)
        txn = extract_entity(context, :transaction)

        if pi.present? && failed_payment_intent?(pi)
          return summarize_pi_failure(pi, context)
        end

        if txn.present? && failed_transaction?(txn)
          return summarize_txn_failure(txn, pi, context)
        end

        SkillResult.failure(
          skill_key: :payment_failure_summary,
          error_code: 'no_failure_data',
          error_message: 'No failed payment intent or transaction data provided.',
          metadata: audit_meta(context)
        )
      rescue StandardError => e
        SkillResult.failure(
          skill_key: :payment_failure_summary,
          error_code: 'execution_error',
          error_message: e.message,
          metadata: audit_meta(context)
        )
      end

      private

      def failed_payment_intent?(pi)
        status = (pi[:status] || pi['status']).to_s
        %w[failed canceled].include?(status)
      end

      def failed_transaction?(txn)
        status = (txn[:status] || txn['status']).to_s.downcase
        status != 'succeeded'
      end

      def summarize_pi_failure(pi, context)
        status = (pi[:status] || pi['status']).to_s
        amount = format_cents(pi[:amount_cents] || pi['amount_cents'])
        currency = (pi[:currency] || pi['currency'] || 'USD').to_s

        explanation = case status
                     when 'failed'
                       "**Payment failure:** Payment Intent ##{pi[:id] || pi['id']} **failed** during authorization or capture. Amount: #{amount} #{currency}. No funds were charged. Check the payment method and try again."
                     when 'canceled'
                       "**Payment voided:** Payment Intent ##{pi[:id] || pi['id']} was **canceled** before capture. Amount: #{amount} #{currency}. No charge was made."
                     else
                       "Payment Intent ##{pi[:id] || pi['id']} is in **#{status}** status. This indicates a failure or void in the lifecycle."
                     end

        SkillResult.success(
          skill_key: :payment_failure_summary,
          data: { status: status, lifecycle_stage: 'payment_intent', entity_type: 'payment_intent' },
          explanation: explanation,
          metadata: audit_meta(context).merge('failure_type' => status),
          deterministic: true
        )
      end

      def summarize_txn_failure(txn, pi, context)
        kind = (txn[:kind] || txn['kind']).to_s
        status = (txn[:status] || txn['status']).to_s
        amount = format_cents(txn[:amount_cents] || txn['amount_cents'])
        id = txn[:id] || txn['id']

        stage = case kind
                when 'authorize' then 'authorization'
                when 'capture' then 'capture'
                when 'refund' then 'refund'
                else kind
                end

        explanation = "**Transaction failure:** Transaction ##{id} (**#{kind}**) **failed**. Status: #{status}. Amount: #{amount}. " \
                     "The failure occurred at the **#{stage}** stage. " \
                     "No funds were transferred for this operation."

        SkillResult.success(
          skill_key: :payment_failure_summary,
          data: { kind: kind, status: status, lifecycle_stage: stage, entity_type: 'transaction' },
          explanation: explanation,
          metadata: audit_meta(context).merge('failure_type' => "#{kind}_failed"),
          deterministic: true
        )
      end

      def extract_entity(context, key)
        case key
        when :payment_intent
          context[:payment_intent] || context['payment_intent']
        when :transaction
          context[:transaction] || context['transaction']
        else
          nil
        end
      end

      def format_cents(cents)
        return '—' if cents.nil?
        Kernel.format('$%.2f', cents.to_i / 100.0)
      end

      def audit_meta(context)
        { 'agent_key' => context[:agent_key].to_s.presence, 'merchant_id' => context[:merchant_id].to_s.presence }.compact
      end

      def missing_context
        SkillResult.failure(
          skill_key: :payment_failure_summary,
          error_code: 'missing_context',
          error_message: 'merchant_id required',
          metadata: {}
        )
      end
    end
  end
end
