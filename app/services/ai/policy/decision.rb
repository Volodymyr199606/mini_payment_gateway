# frozen_string_literal: true

module Ai
  module Policy
    # Immutable result of a policy check. Safe for logging and audit.
    # decision_type: :tool, :orchestration, :memory_reuse, :followup_inheritance,
    #   :source_composition, :debug_exposure, :deterministic_data, :docs_fallback
    Decision = Struct.new(:allowed, :decision_type, :reason_code, :safe_message, :metadata, keyword_init: true) do
      def self.allow(decision_type: nil, metadata: {})
        new(allowed: true, decision_type: decision_type, reason_code: nil, safe_message: nil, metadata: metadata || {})
      end

      def self.deny(reason_code:, decision_type: nil, safe_message: nil, metadata: {})
        new(
          allowed: false,
          decision_type: decision_type,
          reason_code: reason_code.to_s,
          safe_message: safe_message.to_s.strip.presence,
          metadata: metadata || {}
        )
      end

      def allowed?
        allowed
      end

      def denied?
        !allowed
      end
    end
  end
end
