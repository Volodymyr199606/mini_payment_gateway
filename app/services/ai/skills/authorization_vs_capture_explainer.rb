# frozen_string_literal: true

module Ai
  module Skills
    # Explains authorization vs capture lifecycle from deterministic PI status.
    # No LLM; uses domain states only.
    class AuthorizationVsCaptureExplainer < BaseSkill
      DEFINITION = SkillDefinition.new(
        key: :authorization_vs_capture_explainer,
        class_name: 'Ai::Skills::AuthorizationVsCaptureExplainer',
        description: 'Clarify authorization vs capture from payment intent status.',
        deterministic: true,
        dependencies: %i[context tools],
        input_contract: 'payment_intent hash or id, merchant_id',
        output_contract: 'SkillResult with short lifecycle explanation'
      )

      COPY = {
        'created' => 'This payment intent is **created** but not yet authorized—no funds are held.',
        'authorized' => 'Funds are **authorized** (held) but not yet **captured**—capture to settle.',
        'requires_capture' => 'Authorization succeeded; **capture** is still required to collect funds.',
        'captured' => 'Payment has been **captured**—funds were settled.',
        'canceled' => 'The payment intent was **canceled** before capture.',
        'failed' => 'Authorization or processing **failed**—no successful capture.',
        'refunded' => 'The captured amount has been **refunded** (fully or partially).'
      }.freeze

      def execute(context:)
        merchant_id = context[:merchant_id].to_i
        return missing_context unless merchant_id.positive?

        merchant = Merchant.find_by(id: merchant_id)
        return missing_context unless merchant

        pi = resolve_pi(context, merchant)
        return SkillResult.failure(
          skill_key: :authorization_vs_capture_explainer,
          error_code: 'missing_entity',
          error_message: 'Payment intent required.',
          metadata: audit_meta(context)
        ) unless pi

        status = pi.status.to_s
        if pi.respond_to?(:total_refunded_cents) && pi.total_refunded_cents.to_i.positive? && status == 'captured'
          text = COPY['refunded']
        else
          text = COPY[status] || "Current status: **#{status}**. Authorization holds funds; capture completes settlement."
        end

        SkillResult.success(
          skill_key: :authorization_vs_capture_explainer,
          data: { status: status },
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
          skill_key: :authorization_vs_capture_explainer,
          error_code: 'missing_context',
          error_message: 'merchant_id required',
          metadata: {}
        )
      end
    end
  end
end
