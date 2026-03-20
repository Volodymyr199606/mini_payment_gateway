# frozen_string_literal: true

module Api
  module V1
    class WebhooksController < BaseController
      skip_before_action :authenticate_merchant!

      # POST /api/v1/webhooks/processor
      # Receives events from payment processor (simulated)
      def processor
        webhook_event = nil
        payload_body = request.body.read
        provider = Payments::ProviderRegistry.current

        unless provider.verify_webhook_signature(payload: payload_body, headers: request.headers.to_h)
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

        normalized = provider.normalize_webhook_event(payload: payload, headers: request.headers.to_h)
        event_type = normalized[:event_type].to_s
        merchant_id = normalized[:merchant_id]
        signature = normalized[:signature]
        provider_event_id = normalized[:provider_event_id]&.to_s.presence

        merchant = merchant_id ? Merchant.find_by(id: merchant_id) : nil

        # Idempotent: return existing event if already processed (prevents duplicate ingestion)
        if provider_event_id.present?
          existing = WebhookEvent.find_by(provider_event_id: provider_event_id)
          if existing
            render json: {
              data: {
                id: existing.id,
                event_type: existing.event_type,
                status: 'already_received'
              }
            }, status: :ok
            return
          end
        end

        # Create webhook event
        webhook_event = WebhookEvent.create!(
          merchant: merchant,
          event_type: event_type,
          payload: normalized[:payload] || payload,
          delivery_status: 'succeeded', # Already delivered to us
          delivered_at: Time.current,
          signature: signature,
          provider_event_id: provider_event_id
        )

        # Chargeback: set dispute_status on payment intent if identifiable
        if event_type == 'chargeback.opened' && merchant
          payment_intent = resolve_chargeback_payment_intent(normalized, merchant)
          payment_intent&.update!(dispute_status: 'open')
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

      private

      # Resolve PaymentIntent for chargeback: internal ID from metadata, or lookup by provider PI id (processor_ref).
      def resolve_chargeback_payment_intent(normalized, merchant)
        payload = (normalized[:payload] || {}).with_indifferent_access
        data = payload[:data] || payload['data'] || {}

        # Internal payment intent ID (from our metadata on Stripe objects)
        internal_id = data['payment_intent_id'] || data[:payment_intent_id]
        if internal_id.present?
          pi = merchant.payment_intents.find_by(id: internal_id)
          return pi if pi
        end

        # Provider payment intent ID (Stripe pi_xxx) - lookup via processor_ref on authorize transaction
        provider_pi_id = data['provider_payment_intent_id'] || data[:provider_payment_intent_id]
        if provider_pi_id.present?
          return PaymentIntent.joins(:transactions)
            .where(merchant: merchant, transactions: { kind: 'authorize', status: 'succeeded', processor_ref: provider_pi_id })
            .first
        end

        nil
      end
    end
  end
end
