# frozen_string_literal: true

module MiniPaymentGatewayPerf
  # Stubs external I/O and noisy async jobs so perf runs are deterministic and local-safe.
  # Installed once per Ruby process (typical: one `rake perf:*` invocation).
  module Stubs
    module GroqStub
      def chat(*_args, **_kwargs)
        {
          content: 'Perf stub: OK. Short deterministic reply.',
          model_used: 'perf_stub',
          fallback_used: false
        }
      end
    end

    module SilentWebhookJob
      def perform_later(*_args, **_kwargs)
        # Skip ActiveJob enqueue and outbound HTTP for payment-path timings.
        nil
      end
    end

    class DeterministicProvider < Payments::Providers::BaseAdapter
      def authorize(payment_intent:)
        ok_result('auth')
      end

      def capture(payment_intent:)
        ok_result('cap')
      end

      def void(payment_intent:)
        ok_result('void')
      end

      def refund(payment_intent:, amount_cents:)
        ok_result('ref')
      end

      def fetch_status(payment_intent:)
        Payments::ProviderResult.new(success: true, provider_status: payment_intent.status)
      end

      def verify_webhook_signature(payload:, headers:)
        # Controller passes request.headers.to_h — keys are raw Rack names (HTTP_X_WEBHOOK_SIGNATURE),
        # not canonical X-Webhook-Signature.
        sig = headers['HTTP_X_WEBHOOK_SIGNATURE'] ||
              headers['X-Webhook-Signature'] ||
              headers['X-WEBHOOK-SIGNATURE'] ||
              headers['x-webhook-signature']
        expected = WebhookSignatureService.generate_signature(payload, Rails.application.config.webhook_secret)
        return false if sig.blank?

        ActiveSupport::SecurityUtils.secure_compare(expected.to_s, sig.to_s)
      end

      def normalize_webhook_event(payload:, headers:)
        data = payload.is_a?(Hash) ? payload : {}
        sig = headers['HTTP_X_WEBHOOK_SIGNATURE'] ||
              headers['X-Webhook-Signature'] ||
              headers['X-WEBHOOK-SIGNATURE'] ||
              headers['x-webhook-signature']
        {
          event_type: data['event_type'].to_s,
          merchant_id: data.dig('data', 'merchant_id'),
          payload: data,
          signature: sig,
          provider_event_id: data['id']
        }
      end

      private

      def ok_result(prefix)
        Payments::ProviderResult.new(
          success: true,
          processor_ref: "#{prefix}_#{SecureRandom.hex(8)}"
        )
      end
    end

    # Override provider resolution without mutating PAYMENTS_PROVIDER boot config.
    module ProviderRegistryOverride
      def current
        @mini_payment_gateway_perf_stub ||= Stubs::DeterministicProvider.new
      end
    end

    # Skip API rate limits during perf runs (iterations can exceed AI / payment limits).
    module AiRateLimitBypass
      def enforce_prepended_api_rate_limits
        nil
      end

      def enforce_authenticated_api_rate_limits
        nil
      end
    end

    class << self
      def install!
        return if @installed

        Payments::ProviderRegistry.reset!
        Payments::ProviderRegistry.singleton_class.prepend(ProviderRegistryOverride)
        Ai::GroqClient.prepend(GroqStub)
        WebhookDeliveryJob.prepend(SilentWebhookJob)
        Dashboard::AiController.prepend(AiRateLimitBypass)
        Api::V1::Ai::ChatController.prepend(AiRateLimitBypass)
        @installed = true
      end

      def installed?
        @installed == true
      end
    end
  end
end
