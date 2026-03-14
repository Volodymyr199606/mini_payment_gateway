# frozen_string_literal: true

module Ai
  module Performance
    # Structured execution plan for cost/latency control.
    # execution_mode: deterministic_only, docs_only, tool_plus_docs, agent_full, no_memory, no_retrieval, concise_rewrite_only
    ExecutionPlan = Struct.new(
      :execution_mode,
      :skip_retrieval,
      :skip_memory,
      :skip_orchestration,
      :retrieval_budget_reduced,
      :reason_codes,
      :metadata,
      keyword_init: true
    ) do
      def self.full_agent
        new(
          execution_mode: :agent_full,
          skip_retrieval: false,
          skip_memory: false,
          skip_orchestration: false,
          retrieval_budget_reduced: false,
          reason_codes: [],
          metadata: {}
        )
      end

      def retrieval_skipped?
        !!skip_retrieval
      end

      def memory_skipped?
        !!skip_memory
      end

      def orchestration_skipped?
        !!skip_orchestration
      end

      def to_audit_metadata
        {
          execution_mode: execution_mode&.to_s,
          retrieval_skipped: !!skip_retrieval,
          memory_skipped: !!skip_memory,
          orchestration_skipped: !!skip_orchestration,
          retrieval_budget_reduced: !!retrieval_budget_reduced,
          reason_codes: Array(reason_codes)
        }.compact
      end
    end
  end
end
