# frozen_string_literal: true

module Ai
  module Replay
    # Compares original audit metadata vs replayed run metadata. Safe keys only.
    class DiffBuilder
      COMPARABLE_KEYS = %w[
        agent_key composition_mode tool_used tool_names orchestration_used
        orchestration_step_count citations_count retrieved_sections_count
        fallback_used memory_used success
        authorization_denied tool_blocked_by_policy
        deterministic_explanation_used explanation_type explanation_key
        execution_mode retrieval_skipped memory_skipped
        degraded fallback_mode
        skill_keys workflow_key
      ].freeze

      def self.call(original_summary:, replay_summary:)
        new(original_summary: original_summary, replay_summary: replay_summary).call
      end

      def initialize(original_summary:, replay_summary:)
        @original = original_summary.to_h.with_indifferent_access
        @replay = replay_summary.to_h.with_indifferent_access
      end

      def call
        differences = []
        COMPARABLE_KEYS.each do |key|
          orig = normalize(@original[key])
          repl = normalize(@replay[key])
          next if values_equal?(orig, repl)

          differences << {
            field: key,
            original: safe_value(orig),
            replayed: safe_value(repl)
          }
        end
        differences
      end

      def self.matched_flags(original_summary:, replay_summary:)
        orig = original_summary.to_h.with_indifferent_access
        repl = replay_summary.to_h.with_indifferent_access

        {
          matched_path: path_match?(orig, repl),
          matched_policy_decisions: policy_match?(orig, repl),
          matched_tool_usage: tool_usage_match?(orig, repl),
          matched_skill_usage: skill_usage_match?(orig, repl),
          matched_composition_mode: orig[:composition_mode].to_s == repl[:composition_mode].to_s,
          matched_debug_metadata: composition_and_tools_match?(orig, repl)
        }
      end

      class << self
        private

        def path_match?(orig, repl)
          orig[:composition_mode].to_s == repl[:composition_mode].to_s &&
            (orig[:execution_mode].to_s.presence || 'n/a') == (repl[:execution_mode].to_s.presence || 'n/a')
        end

        def policy_match?(orig, repl)
          orig[:authorization_denied] == repl[:authorization_denied] &&
            orig[:tool_blocked_by_policy] == repl[:tool_blocked_by_policy]
        end

        def tool_usage_match?(orig, repl)
          Array(orig[:tool_names]).sort == Array(repl[:tool_names]).sort &&
            !!orig[:tool_used] == !!repl[:tool_used]
        end

        def skill_usage_match?(orig, repl)
          Array(orig[:skill_keys]).sort == Array(repl[:skill_keys]).sort
        end

        def composition_and_tools_match?(orig, repl)
          orig[:composition_mode].to_s == repl[:composition_mode].to_s &&
            Array(orig[:tool_names]).sort == Array(repl[:tool_names]).sort
        end
      end

      private

      def normalize(v)
        return Array(v).map(&:to_s).sort if v.is_a?(Array)
        v
      end

      def values_equal?(a, b)
        return a == b unless a.is_a?(Array) && b.is_a?(Array)
        a.sort == b.sort
      end

      def safe_value(v)
        return v unless v.is_a?(Hash)
        v.transform_keys(&:to_s).slice(*COMPARABLE_KEYS)
      end
    end
  end
end
