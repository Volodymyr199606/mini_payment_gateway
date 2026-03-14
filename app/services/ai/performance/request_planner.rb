# frozen_string_literal: true

module Ai
  module Performance
    # Cost/latency planning. Chooses cheapest safe path before execution.
    class RequestPlanner
      EXECUTION_MODES = %i[
        deterministic_only
        docs_only
        tool_plus_docs
        agent_full
        no_memory
        no_retrieval
        concise_rewrite_only
      ].freeze

      REWRITE_PHRASES = /\b(simpler|shorter|more\s+detailed|bullet\s*points?|only\s+(?:the\s+)?important|just\s+the\s+key)\b/i
      REFERENCE_WORDS = /\b(that|it|those|this|same)\b/i

      # Agent-aware defaults: prefer lighter paths when safe
      AGENT_PREFERENCE = {
        reporting_calculation: { retrieval: :minimal, memory: :skip_standalone },
        support_faq: { retrieval: :full, memory: :full },
        security_compliance: { retrieval: :full, memory: :skip_standalone },
        developer_onboarding: { retrieval: :full, memory: :skip_standalone },
        operational: { retrieval: :full, memory: :skip_standalone },
        reconciliation_analyst: { retrieval: :full, memory: :skip_standalone }
      }.freeze

      def self.plan(message:, intent_resolution: {}, agent_key: nil)
        new(message: message, intent_resolution: intent_resolution, agent_key: agent_key).plan
      end

      def initialize(message:, intent_resolution: {}, agent_key: nil)
        @message = message.to_s.strip
        @intent = intent_resolution[:intent]
        @followup = intent_resolution[:followup] || {}
        @agent_key = (agent_key || infer_agent_key).to_s.to_sym
      end

      def plan
        # Deterministic path: intent present → orchestration will handle; no planner changes
        if @intent.present?
          return ExecutionPlan.new(
            execution_mode: :deterministic_only,
            skip_retrieval: true,
            skip_memory: true,
            skip_orchestration: false,
            retrieval_budget_reduced: false,
            reason_codes: %w[intent_present deterministic_sufficient],
            metadata: { tool_name: @intent[:tool_name] }
          )
        end

        # Agent path: plan retrieval/memory
        plan_agent_path
      end

      private

      def plan_agent_path
        followup_detected = !!@followup[:followup_detected]
        followup_type = @followup[:followup_type]
        rewrite_only = concise_rewrite?(followup_type)
        standalone = !followup_detected

        skip_retrieval = false
        skip_memory = false
        retrieval_budget_reduced = false
        reason_codes = []
        mode = :agent_full

        if rewrite_only && prior_has_content?
          # Lightweight rewrite: reduce retrieval, use minimal context
          retrieval_budget_reduced = true
          reason_codes << 'concise_rewrite'
          mode = :concise_rewrite_only
        end

        if standalone
          pref = AGENT_PREFERENCE[@agent_key]
          skip_memory = pref&.dig(:memory) == :skip_standalone
          reason_codes << 'standalone_no_followup' if skip_memory
        end

        if retrieval_budget_reduced
          reason_codes << 'narrow_question'
        end

        ExecutionPlan.new(
          execution_mode: mode,
          skip_retrieval: skip_retrieval,
          skip_memory: skip_memory,
          skip_orchestration: true, # We're in agent path; orchestration already skipped
          retrieval_budget_reduced: retrieval_budget_reduced,
          reason_codes: reason_codes.presence || ['agent_full'],
          metadata: { agent_key: @agent_key, followup_type: followup_type }
        )
      end

      def concise_rewrite?(followup_type)
        return false unless followup_type == :explanation_rewrite
        return false if @message.length > 80
        REWRITE_PHRASES.match?(@message)
      end

      def prior_has_content?
        prior = @followup[:prior_intent]
        prior.present? || @followup[:inherited_entities].present? || @followup[:inherited_time_range].present?
      end

      def infer_agent_key
        ::Ai::Router.new(@message).call
      end
    end
  end
end
