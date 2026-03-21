# frozen_string_literal: true

module Ai
  module Skills
    # Explains webhook event delivery status and lifecycle. Reuses
    # Ai::Explanations::Renderer and TemplateRegistry. Deterministic.
    class WebhookTraceExplainer < BaseSkill
      DEFINITION = SkillDefinition.new(
        key: :webhook_trace_explainer,
        class_name: 'Ai::Skills::WebhookTraceExplainer',
        description: 'Explain webhook delivery and status from merchant data.',
        deterministic: true,
        dependencies: %i[tools context],
        input_contract: 'webhook_event_id or pre-fetched webhook_event hash, merchant_id',
        output_contract: 'SkillResult with trace summary, delivery_status, metadata'
      )

      def execute(context:)
        merchant_id = context[:merchant_id].to_i
        return missing_context_error unless merchant_id.present?

        merchant = Merchant.find_by(id: merchant_id)
        return missing_context_error unless merchant

        data = resolve_webhook_data(context, merchant)
        return entity_not_found_error(context) unless data

        render_and_return(data, context)
      rescue StandardError => e
        SkillResult.failure(
          skill_key: :webhook_trace_explainer,
          error_code: 'execution_error',
          error_message: e.message,
          metadata: audit_metadata(context)
        )
      end

      private

      def resolve_webhook_data(context, merchant)
        if context[:webhook_event].is_a?(Hash)
          normalize_webhook_hash(context[:webhook_event])
        elsif (wid = context[:webhook_event_id].to_s.strip.presence&.to_i)
          evt = merchant.webhook_events.find_by(id: wid)
          evt ? serialize_webhook(evt) : nil
        end
      end

      def serialize_webhook(evt)
        {
          id: evt.id,
          event_type: evt.event_type,
          delivery_status: evt.delivery_status,
          attempts: evt.attempts.to_i
        }
      end

      def normalize_webhook_hash(h)
        h = h.deep_symbolize_keys
        {
          id: h[:id],
          event_type: (h[:event_type] || 'unknown').to_s,
          delivery_status: (h[:delivery_status] || 'pending').to_s,
          attempts: h[:attempts].to_i
        }.compact
      end

      def render_and_return(data, context)
        rendered = Explanations::Renderer.render('get_webhook_event', data)
        explanation = rendered&.explanation_text || build_fallback(data)

        SkillResult.success(
          skill_key: :webhook_trace_explainer,
          data: {
            explanation_text: explanation,
            event_type: data[:event_type],
            delivery_status: data[:delivery_status],
            attempts: data[:attempts]
          },
          explanation: explanation,
          metadata: audit_metadata(context).merge(
            'explanation_type' => 'webhook_event',
            'delivery_status' => data[:delivery_status]
          ),
          deterministic: true
        )
      end

      def build_fallback(data)
        "Webhook event ##{data[:id]}: #{data[:event_type]}. Delivery: #{data[:delivery_status]}. Attempts: #{data[:attempts]}."
      end

      def audit_metadata(context)
        {
          'agent_key' => context[:agent_key].to_s.presence,
          'merchant_id' => context[:merchant_id].to_s.presence
        }.compact
      end

      def missing_context_error
        SkillResult.failure(
          skill_key: :webhook_trace_explainer,
          error_code: 'missing_context',
          error_message: 'merchant_id required',
          metadata: {}
        )
      end

      def entity_not_found_error(context)
        SkillResult.failure(
          skill_key: :webhook_trace_explainer,
          error_code: 'entity_not_found',
          error_message: 'Provide webhook_event_id or webhook_event data. Webhook not found or access denied.',
          metadata: audit_metadata(context)
        )
      end
    end
  end
end
