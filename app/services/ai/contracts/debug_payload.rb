# frozen_string_literal: true

module Ai
  module Contracts
    # Contract for AI debug payload (EventLogger.build_debug_payload, controller debug).
    # Non-sensitive only. Includes schema_version for evolution.
    class DebugPayload
      attr_reader :payload, :schema_version

      # Safe debug keys (no prompts, secrets, or raw payloads).
      STABLE_KEYS = %w[
        selected_agent selected_retriever graph_enabled vector_enabled
        retrieved_sections_count citations_count fallback_used citation_reask_used
        model_used memory_used summary_used latency_ms authorization_checked
        authorization_denied tool_blocked_by_policy followup_inheritance_blocked
        policy_reason_code policy_decision_types cache corpus_version
        retrieval_corpus_version resilience execution_plan
      ].freeze

      def initialize(payload: {}, schema_version: nil)
        @payload = payload.is_a?(Hash) ? payload : {}
        @schema_version = schema_version || Contracts::DEBUG_PAYLOAD_VERSION
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
