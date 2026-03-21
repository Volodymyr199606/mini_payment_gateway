# frozen_string_literal: true

module Ai
  module Skills
    # Explains payment intent or transaction status using deterministic templates.
    # Reuses Ai::Explanations::Renderer and TemplateRegistry. Bounded, auditable.
    class PaymentStateExplainer < BaseSkill
      DEFINITION = SkillDefinition.new(
        key: :payment_state_explainer,
        class_name: 'Ai::Skills::PaymentStateExplainer',
        description: 'Explain payment intent lifecycle states using domain semantics.',
        deterministic: true,
        dependencies: %i[context tools],
        input_contract: 'payment_intent_id or transaction_id or pre-fetched entity hashes, merchant_id',
        output_contract: 'SkillResult with explanation_text, explanation_type, explanation_key, metadata'
      )

      def execute(context:)
        merchant_id = context[:merchant_id].to_i
        return missing_context_error unless merchant_id.present?

        merchant = Merchant.find_by(id: merchant_id)
        return missing_context_error unless merchant

        if (pi_data = resolve_payment_intent_data(context, merchant))
          render_and_return('get_payment_intent', pi_data, context)
        elsif (txn_data = resolve_transaction_data(context, merchant))
          render_and_return('get_transaction', txn_data, context)
        else
          SkillResult.failure(
            skill_key: :payment_state_explainer,
            error_code: 'missing_entity',
            error_message: 'Provide payment_intent_id, transaction_id, or pre-fetched payment_intent/transaction data.',
            metadata: audit_metadata(context)
          )
        end
      rescue StandardError => e
        SkillResult.failure(
          skill_key: :payment_state_explainer,
          error_code: 'execution_error',
          error_message: e.message,
          metadata: audit_metadata(context)
        )
      end

      private

      def resolve_payment_intent_data(context, merchant)
        if context[:payment_intent].is_a?(Hash)
          normalize_pi_hash(context[:payment_intent])
        elsif (pid = context[:payment_intent_id].to_s.strip.presence&.to_i)
          pi = merchant.payment_intents.find_by(id: pid)
          pi ? serialize_payment_intent(pi) : nil
        end
      end

      def resolve_transaction_data(context, merchant)
        if context[:transaction].is_a?(Hash)
          normalize_txn_hash(context[:transaction])
        elsif (tid = context[:transaction_id].to_s.strip.presence&.to_i)
          txn = Transaction.joins(:payment_intent).where(payment_intents: { merchant_id: merchant.id }).find_by(id: tid)
          txn ? serialize_transaction(txn) : nil
        elsif (ref = context[:processor_ref].to_s.strip.presence)
          txn = Transaction.joins(:payment_intent).where(payment_intents: { merchant_id: merchant.id }).find_by(processor_ref: ref)
          txn ? serialize_transaction(txn) : nil
        end
      end

      def serialize_payment_intent(pi)
        data = {
          id: pi.id,
          amount_cents: pi.amount_cents,
          currency: pi.currency,
          status: pi.status,
          dispute_status: pi.dispute_status
        }
        refunded = pi.respond_to?(:total_refunded_cents) && pi.total_refunded_cents.to_i.positive?
        data[:status] = 'refunded' if refunded && pi.status == 'captured'
        data[:total_refunded_cents] = pi.total_refunded_cents if refunded
        data
      end

      def serialize_transaction(txn)
        {
          id: txn.id,
          kind: txn.kind,
          status: txn.status,
          amount_cents: txn.amount_cents,
          processor_ref: txn.processor_ref.presence || '—'
        }
      end

      def normalize_pi_hash(h)
        h = h.deep_symbolize_keys
        {
          id: h[:id],
          amount_cents: h[:amount_cents].to_i,
          currency: (h[:currency] || 'USD').to_s,
          status: (h[:status] || 'created').to_s,
          dispute_status: (h[:dispute_status] || 'none').to_s
        }.compact
      end

      def normalize_txn_hash(h)
        h = h.deep_symbolize_keys
        {
          id: h[:id],
          kind: (h[:kind] || 'unknown').to_s,
          status: (h[:status] || 'unknown').to_s,
          amount_cents: h[:amount_cents].to_i,
          processor_ref: (h[:processor_ref].presence || '—').to_s
        }.compact
      end

      def render_and_return(tool_name, data, context)
        rendered = Explanations::Renderer.render(tool_name, data)
        unless rendered
          return SkillResult.failure(
            skill_key: :payment_state_explainer,
            error_code: 'no_template',
            error_message: "No template for #{tool_name} with given data.",
            metadata: audit_metadata(context)
          )
        end

        explanation = rendered.explanation_text
        if data[:total_refunded_cents].to_i.positive?
          amount = format_money(data[:total_refunded_cents] / 100.0)
          explanation += " Total refunded: #{amount}."
        end

        SkillResult.success(
          skill_key: :payment_state_explainer,
          data: {
            explanation_text: explanation,
            explanation_type: rendered.explanation_type,
            explanation_key: rendered.explanation_key
          },
          explanation: explanation,
          metadata: audit_metadata(context).merge(
            'explanation_type' => rendered.explanation_type,
            'explanation_key' => rendered.explanation_key
          ),
          deterministic: true
        )
      end

      def format_money(amount)
        Kernel.format('$%.2f', amount.to_f)
      end

      def audit_metadata(context)
        {
          'agent_key' => context[:agent_key].to_s.presence,
          'merchant_id' => context[:merchant_id].to_s.presence
        }.compact
      end

      def missing_context_error
        SkillResult.failure(
          skill_key: :payment_state_explainer,
          error_code: 'missing_context',
          error_message: 'merchant_id required',
          metadata: {}
        )
      end
    end
  end
end
