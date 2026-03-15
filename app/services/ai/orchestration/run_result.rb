# frozen_string_literal: true

module Ai
  module Orchestration
    # Result of a constrained multi-step tool run. Used for audit, debug, and response composition.
    # Deterministic data is the source of truth; no LLM override.
    # Contract: stable fields; contract_version for serialization/audit.
    class RunResult
      CONTRACT_VERSION = (defined?(Ai::Contracts) && Ai::Contracts::RUN_RESULT_VERSION) || '1'

      attr_reader :orchestration_used,
                  :step_count,
                  :steps,
                  :tool_names,
                  :success,
                  :halted_reason,
                  :deterministic_data,
                  :metadata,
                  :reply_text,
                  :explanation_metadata

      def initialize(
        orchestration_used: false,
        step_count: 0,
        steps: [],
        tool_names: [],
        success: false,
        halted_reason: nil,
        deterministic_data: nil,
        metadata: {},
        reply_text: '',
        explanation_metadata: nil
      )
        @orchestration_used = !!orchestration_used
        @step_count = step_count.to_i
        @steps = steps.to_a.freeze
        @tool_names = tool_names.to_a.freeze
        @success = !!success
        @halted_reason = halted_reason.to_s.strip.presence
        @deterministic_data = deterministic_data
        @metadata = metadata.to_h.freeze
        @reply_text = reply_text.to_s
        @explanation_metadata = explanation_metadata.is_a?(Hash) ? explanation_metadata.freeze : nil
      end

      def self.no_orchestration
        new(orchestration_used: false, step_count: 0, success: false)
      end

      def orchestration_used?
        @orchestration_used
      end

      def success?
        @success
      end

      # Safe per-step summaries for debug (no secrets, no raw payloads).
      def step_summaries_for_debug
        @steps.map do |s|
          {
            tool_name: s[:tool_name],
            success: s[:success],
            result_summary: s[:result_summary],
            latency_ms: s[:latency_ms]
          }.compact
        end
      end

      def to_h
        {
          orchestration_used: @orchestration_used,
          step_count: @step_count,
          tool_names: @tool_names.to_a,
          success: @success,
          halted_reason: @halted_reason,
          reply_text: @reply_text,
          explanation_metadata: @explanation_metadata,
          contract_version: CONTRACT_VERSION
        }.compact
      end
    end
  end
end
