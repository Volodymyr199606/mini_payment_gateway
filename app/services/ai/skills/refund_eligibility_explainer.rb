# frozen_string_literal: true

module Ai
  module Skills
    # Bounded explanation of refund eligibility from PaymentIntent domain logic.
    # Uses refundable_cents / total_refunded_cents; does not bypass RefundService.
    class RefundEligibilityExplainer < BaseSkill
      DEFINITION = SkillDefinition.new(
        key: :refund_eligibility_explainer,
        class_name: 'Ai::Skills::RefundEligibilityExplainer',
        description: 'Explain remaining refundable amount from captured payment intent state.',
        deterministic: true,
        dependencies: %i[context tools],
        input_contract: 'merchant_id, payment_intent id or hash',
        output_contract: 'SkillResult with bounded refund eligibility text'
      )

      def execute(context:)
        merchant_id = context[:merchant_id].to_i
        return missing_context unless merchant_id.positive?

        merchant = Merchant.find_by(id: merchant_id)
        return missing_context unless merchant

        pi = resolve_pi(context, merchant)
        return SkillResult.failure(
          skill_key: :refund_eligibility_explainer,
          error_code: 'missing_entity',
          error_message: 'Payment intent required.',
          metadata: audit_meta(context)
        ) unless pi

        unless pi.status == 'captured'
          text = "Payment Intent ##{pi.id} is **#{pi.status}**. Refunds apply only after a successful capture."
          return SkillResult.success(
            skill_key: :refund_eligibility_explainer,
            data: { eligible: false, status: pi.status },
            explanation: text,
            metadata: audit_meta(context),
            deterministic: true
          )
        end

        refundable = pi.refundable_cents
        refunded = pi.total_refunded_cents
        money = ->(c) { Kernel.format('$%.2f', c / 100.0) }

        text = if refundable.positive?
                 "**Refund eligibility:** Up to #{money.call(refundable)} remains refundable (total refunded so far: #{money.call(refunded)})."
               else
                 '**Refund eligibility:** No remaining refundable amount for this payment intent.'
               end

        SkillResult.success(
          skill_key: :refund_eligibility_explainer,
          data: { refundable_cents: refundable, total_refunded_cents: refunded, eligible: refundable.positive? },
          explanation: text,
          metadata: audit_meta(context),
          deterministic: true
        )
      end

      private

      def resolve_pi(context, merchant)
        if context[:payment_intent].is_a?(Hash)
          id = context[:payment_intent][:id] || context[:payment_intent]['id']
          merchant.payment_intents.find_by(id: id) if id
        elsif (pid = context[:payment_intent_id].to_s.strip.presence&.to_i)
          merchant.payment_intents.find_by(id: pid)
        end
      end

      def audit_meta(context)
        { 'agent_key' => context[:agent_key].to_s.presence, 'merchant_id' => context[:merchant_id].to_s.presence }.compact
      end

      def missing_context
        SkillResult.failure(
          skill_key: :refund_eligibility_explainer,
          error_code: 'missing_context',
          error_message: 'merchant_id required',
          metadata: {}
        )
      end
    end
  end
end
