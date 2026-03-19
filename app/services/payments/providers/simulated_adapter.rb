# frozen_string_literal: true

module Payments
  module Providers
    class SimulatedAdapter < BaseAdapter
      def authorize(payment_intent:)
        success = rand > 0.1
        if success
          ProviderResult.new(success: true, processor_ref: generated_ref('sim_auth'))
        else
          ProviderResult.new(success: false, failure_code: 'insufficient_funds', failure_message: 'Insufficient funds')
        end
      end

      def capture(payment_intent:)
        success = rand > 0.05
        if success
          ProviderResult.new(success: true, processor_ref: generated_ref('sim_cap'))
        else
          ProviderResult.new(success: false, failure_code: 'capture_failed', failure_message: 'Capture failed')
        end
      end

      def void(payment_intent:)
        success = rand > 0.02
        if success
          ProviderResult.new(success: true, processor_ref: generated_ref('sim_void'))
        else
          ProviderResult.new(success: false, failure_code: 'void_failed', failure_message: 'Void failed')
        end
      end

      def refund(payment_intent:, amount_cents:)
        success = rand > 0.01
        if success
          ProviderResult.new(success: true, processor_ref: generated_ref('sim_ref'))
        else
          ProviderResult.new(success: false, failure_code: 'refund_failed', failure_message: 'Refund failed')
        end
      end

      def fetch_status(payment_intent:)
        ProviderResult.new(success: true, provider_status: payment_intent.status)
      end

      def verify_webhook_signature(payload:, headers:)
        signature = header_value(headers, 'X-WEBHOOK-SIGNATURE')
        expected = WebhookSignatureService.generate_signature(payload, Rails.application.config.webhook_secret)
        ActiveSupport::SecurityUtils.secure_compare(expected, signature.to_s)
      end

      def normalize_webhook_event(payload:, headers:)
        data = payload.is_a?(Hash) ? payload : {}
        {
          event_type: data['event_type'].to_s,
          merchant_id: data.dig('data', 'merchant_id'),
          payload: data,
          signature: header_value(headers, 'X-WEBHOOK-SIGNATURE'),
          provider_event_id: data['id']
        }
      end

      private

      def generated_ref(prefix)
        "#{prefix}_#{SecureRandom.hex(12)}"
      end

      def header_value(headers, key)
        headers[key] || headers[key.downcase] || headers[key.upcase]
      end
    end
  end
end
