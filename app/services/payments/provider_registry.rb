# frozen_string_literal: true

module Payments
  class ProviderRegistry
    class << self
      def current
        @current ||= build(Config.provider)
      end

      def reset!
        @current = nil
      end

      def build(provider_name)
        case provider_name.to_s
        when 'simulated'
          Providers::SimulatedAdapter.new
        when 'stripe_sandbox'
          Providers::StripeAdapter.new
        else
          raise Payments::ProviderConfigurationError, "Unknown payment provider: #{provider_name.inspect}"
        end
      end
    end
  end
end
