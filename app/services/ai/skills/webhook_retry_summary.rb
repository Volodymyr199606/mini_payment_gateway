# frozen_string_literal: true

module Ai
  module Skills
    # Summarizes webhook retry status and operational meaning.
    # Reuses webhook event data from context. Deterministic.
    class WebhookRetrySummary < BaseSkill
      MAX_ATTEMPTS = 3 # Matches WebhookDeliveryService

      DEFINITION = SkillDefinition.new(
        key: :webhook_retry_summary,
        class_name: 'Ai::Skills::WebhookRetrySummary',
        description: 'Summarize webhook delivery retry status and operational meaning.',
        deterministic: true,
        dependencies: %i[tools context],
        input_contract: 'webhook_event hash with delivery_status, attempts, merchant_id',
        output_contract: 'SkillResult with retry summary and operator guidance'
      )

      def execute(context:)
        merchant_id = context[:merchant_id].to_i
        return missing_context unless merchant_id.positive?

        webhook = resolve_webhook(context)
        return no_data(context) unless webhook

        status = (webhook[:delivery_status] || webhook['delivery_status']).to_s.downcase
        attempts = (webhook[:attempts] || webhook['attempts']).to_i
        event_type = (webhook[:event_type] || webhook['event_type']).to_s
        id = webhook[:id] || webhook['id']

        explanation = build_summary(id, event_type, status, attempts)

        SkillResult.success(
          skill_key: :webhook_retry_summary,
          data: {
            delivery_status: status,
            attempts: attempts,
            max_attempts: MAX_ATTEMPTS,
            event_type: event_type
          },
          explanation: explanation,
          metadata: audit_meta(context).merge('delivery_status' => status),
          deterministic: true
        )
      rescue StandardError => e
        SkillResult.failure(
          skill_key: :webhook_retry_summary,
          error_code: 'execution_error',
          error_message: e.message,
          metadata: audit_meta(context)
        )
      end

      private

      def resolve_webhook(context)
        data = context[:deterministic_data] || context['deterministic_data'] || {}
        data = data.with_indifferent_access if data.respond_to?(:with_indifferent_access)
        webhook = data[:webhook_event] || data['webhook_event']
        return webhook if webhook.present?

        context[:webhook_event] || context['webhook_event']
      end

      def build_summary(id, event_type, status, attempts)
        case status
        when 'succeeded'
          "**Webhook delivered:** Event ##{id} (#{event_type}) was **delivered successfully** after #{attempts} attempt(s). No further action needed."
        when 'failed'
          "**Webhook delivery exhausted:** Event ##{id} (#{event_type}) **failed** after #{attempts} attempt(s) (max: #{MAX_ATTEMPTS}). " \
            "Delivery will not be retried. Review your endpoint and consider reprocessing manually if needed."
        when 'pending'
          retry_msg = attempts.positive? ? "Retrying (attempt #{attempts}/#{MAX_ATTEMPTS})." : "Delivery pending (no attempts yet)."
          "**Webhook retrying:** Event ##{id} (#{event_type}) is **pending**. #{retry_msg} " \
            "Check your endpoint availability; delivery will retry with backoff."
        else
          "Webhook event ##{id} (#{event_type}): delivery status **#{status}**, #{attempts} attempt(s)."
        end
      end

      def audit_meta(context)
        { 'agent_key' => context[:agent_key].to_s.presence, 'merchant_id' => context[:merchant_id].to_s.presence }.compact
      end

      def missing_context
        SkillResult.failure(
          skill_key: :webhook_retry_summary,
          error_code: 'missing_context',
          error_message: 'merchant_id required',
          metadata: {}
        )
      end

      def no_data(context)
        SkillResult.failure(
          skill_key: :webhook_retry_summary,
          error_code: 'no_webhook_data',
          error_message: 'No webhook event data provided.',
          metadata: audit_meta(context)
        )
      end
    end
  end
end
