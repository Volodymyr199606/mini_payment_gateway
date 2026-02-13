# frozen_string_literal: true

module Api
  module V1
    class WebhooksController < BaseController
      skip_before_action :authenticate_merchant!

      # POST /api/v1/webhooks/processor
      # Receives events from payment processor (simulated)
      def processor
        webhook_event = nil
        signature = request.headers['X-WEBHOOK-SIGNATURE']
        payload_body = request.body.read

        # Verify signature
        signature_service = WebhookSignatureService.call(
          payload: payload_body,
          signature: signature
        )

        unless signature_service.success?
          render_error(
            code: 'invalid_signature',
            message: 'Invalid webhook signature',
            status: :unauthorized
          )
          return
        end

        # Parse payload
        begin
          payload = JSON.parse(payload_body)
        rescue JSON::ParserError
          render_error(
            code: 'invalid_payload',
            message: 'Invalid JSON payload',
            status: :bad_request
          )
          return
        end

        event_type = payload['event_type']
        merchant_id = payload.dig('data', 'merchant_id')

        merchant = merchant_id ? Merchant.find_by(id: merchant_id) : nil

        # Create webhook event
        webhook_event = WebhookEvent.create!(
          merchant: merchant,
          event_type: event_type,
          payload: payload,
          delivery_status: 'succeeded', # Already delivered to us
          delivered_at: Time.current,
          signature: signature
        )

        # Chargeback: set dispute_status on payment intent if identifiable
        if event_type == 'chargeback.opened'
          pi_id = payload.dig('data', 'payment_intent_id')
          if pi_id && merchant
            pi = merchant.payment_intents.find_by(id: pi_id)
            pi&.update!(dispute_status: 'open')
          end
        end

        # Queue delivery to merchant (if configured)
        WebhookDeliveryJob.perform_later(webhook_event.id)

        render json: {
          data: {
            id: webhook_event.id,
            event_type: webhook_event.event_type,
            status: 'received'
          }
        }, status: :created
      rescue StandardError => e
        Rails.logger.error(SafeLogHelper.safe_error_payload(
          event: 'webhook_processing_error',
          exception: e,
          webhook_event_id: webhook_event&.id,
          request_id: request.env['request_id'] || Thread.current[:request_id]
        ))
        render_error(
          code: 'processing_error',
          message: 'Failed to process webhook',
          status: :internal_server_error
        )
      end
    end
  end
end
