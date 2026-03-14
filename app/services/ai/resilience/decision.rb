# frozen_string_literal: true

module Ai
  module Resilience
    # Structured result of a resilience/fallback decision.
    # failure_stage: generation, retrieval, tool, orchestration, memory, streaming, audit_debug
    # fallback_mode: normal, tool_only, docs_only, no_memory, no_orchestration, non_streaming_fallback, safe_failure_message
    Decision = Struct.new(:degraded, :failure_stage, :fallback_mode, :safe_message, :metadata, :retry_allowed, keyword_init: true) do
      def self.normal
        new(degraded: false, failure_stage: nil, fallback_mode: :normal, safe_message: nil, metadata: {}, retry_allowed: false)
      end

      def self.degrade(failure_stage:, fallback_mode:, safe_message:, metadata: {}, retry_allowed: false)
        new(
          degraded: true,
          failure_stage: failure_stage,
          fallback_mode: fallback_mode,
          safe_message: safe_message,
          metadata: metadata,
          retry_allowed: retry_allowed
        )
      end

      def degraded?
        !!degraded
      end
    end
  end
end
