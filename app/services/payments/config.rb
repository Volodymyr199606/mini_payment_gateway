# frozen_string_literal: true

module Payments
  # Keep core provider errors colocated with runtime config to ensure constants
  # are available whenever provider config is evaluated at boot.
  class ProviderError < StandardError; end unless const_defined?(:ProviderError)
  class ProviderConfigurationError < ProviderError; end unless const_defined?(:ProviderConfigurationError)
  class ProviderRequestError < ProviderError; end unless const_defined?(:ProviderRequestError)
  class ProviderSignatureError < ProviderError; end unless const_defined?(:ProviderSignatureError)

  module Config
    SUPPORTED_PROVIDERS = %w[simulated stripe_sandbox].freeze

    class << self
      def provider
        ENV.fetch('PAYMENTS_PROVIDER', 'simulated').to_s.strip.presence || 'simulated'
      end

      def timeout_seconds
        ENV.fetch('PROCESSOR_TIMEOUT_SECONDS', '3').to_i
      end

      def stripe_base_url
        ENV.fetch('STRIPE_BASE_URL', 'https://api.stripe.com')
      end

      def stripe_api_key
        ENV['STRIPE_SECRET_KEY'].to_s.strip
      end

      def stripe_webhook_secret
        ENV['STRIPE_WEBHOOK_SECRET'].to_s.strip
      end

      def validate!(raise_in_current_env: default_raise?)
        errors = []

        unless SUPPORTED_PROVIDERS.include?(provider)
          errors << "Unsupported PAYMENTS_PROVIDER=#{provider.inspect}. Supported: #{SUPPORTED_PROVIDERS.join(', ')}"
        end

        if provider == 'stripe_sandbox'
          errors << 'STRIPE_SECRET_KEY is required when PAYMENTS_PROVIDER=stripe_sandbox' if stripe_api_key.blank?
          errors << 'STRIPE_WEBHOOK_SECRET is required when PAYMENTS_PROVIDER=stripe_sandbox' if stripe_webhook_secret.blank?
        end

        return if errors.empty?

        message = "[Payments::Config] #{errors.join(' | ')}"
        Rails.logger.error(message)
        raise ProviderConfigurationError, message if raise_in_current_env
      end

      private

      def default_raise?
        Rails.env.development? || Rails.env.test?
      end
    end
  end
end
