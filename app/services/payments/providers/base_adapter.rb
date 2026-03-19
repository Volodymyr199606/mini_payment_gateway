# frozen_string_literal: true

module Payments
  module Providers
    class BaseAdapter
      def authorize(payment_intent:)
        raise NotImplementedError, "#{self.class.name} must implement #authorize"
      end

      def capture(payment_intent:)
        raise NotImplementedError, "#{self.class.name} must implement #capture"
      end

      def void(payment_intent:)
        raise NotImplementedError, "#{self.class.name} must implement #void"
      end

      def refund(payment_intent:, amount_cents:)
        raise NotImplementedError, "#{self.class.name} must implement #refund"
      end

      def fetch_status(payment_intent:)
        raise NotImplementedError, "#{self.class.name} must implement #fetch_status"
      end

      def verify_webhook_signature(payload:, headers:)
        raise NotImplementedError, "#{self.class.name} must implement #verify_webhook_signature"
      end

      def normalize_webhook_event(payload:, headers:)
        raise NotImplementedError, "#{self.class.name} must implement #normalize_webhook_event"
      end
    end
  end
end
