# frozen_string_literal: true

module Ai
  module Contracts
    # Contract for AI request audit payload (RecordBuilder output, Writer input).
    # Stable keys align with ai_request_audits schema. Includes schema_version for evolution.
    class AuditPayload
      attr_reader :payload, :schema_version

      # Keys that are always present (or have safe defaults) in persisted audit.
      STABLE_KEYS = %w[
        request_id endpoint merchant_id agent_key retriever_key composition_mode
        tool_used tool_names fallback_used citation_reask_used memory_used summary_used
        parsed_entities parsed_intent_hints citations_count retrieved_sections_count
        latency_ms model_used success error_class error_message created_at
        followup_detected followup_type authorization_denied policy_reason_code
        tool_blocked_by_policy followup_inheritance_blocked corpus_version
        deterministic_explanation_used explanation_type explanation_key
        orchestration_used orchestration_step_count orchestration_halted_reason
      ].freeze

      def initialize(payload: {}, schema_version: nil)
        @payload = payload.is_a?(Hash) ? payload : {}
        @schema_version = schema_version || Contracts::AUDIT_PAYLOAD_VERSION
      end

      def self.from_h(h)
        return nil if h.blank? || !h.is_a?(Hash)

        sym = h.with_indifferent_access
        new(
          payload: sym.except(:schema_version),
          schema_version: sym[:schema_version].presence
        )
      end

      def to_h
        @payload.merge(schema_version: @schema_version)
      end

      def []=(key, value)
        @payload[key.to_sym] = value
      end

      def [](key)
        @payload[key.to_sym]
      end
    end
  end
end
