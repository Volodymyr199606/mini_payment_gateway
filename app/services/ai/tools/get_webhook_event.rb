# frozen_string_literal: true

module Ai
  module Tools
    # Fetch webhook event by id, scoped to merchant. Read-only.
    class GetWebhookEvent < BaseTool
      def call
        return error('merchant_id required') unless merchant_id.present?
        return error('webhook_event_id required') unless id.present?

        evt = merchant.webhook_events.find_by(id: id)
        return error('Webhook event not found', code: 'not_found') unless evt

        ok(serialize(evt))
      rescue StandardError => e
        error(e.message, code: 'tool_error')
      end

      private

      def id
        @id ||= @args['webhook_event_id'].to_s.strip.presence&.to_i
      end

      def serialize(evt)
        {
          id: evt.id,
          merchant_id: evt.merchant_id,
          event_type: evt.event_type,
          delivery_status: evt.delivery_status,
          attempts: evt.attempts,
          created_at: evt.created_at.iso8601
        }
      end
    end
  end
end
