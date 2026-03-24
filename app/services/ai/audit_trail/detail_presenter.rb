# frozen_string_literal: true

module Ai
  module AuditTrail
    # Formats a single AiRequestAudit for internal drill-down display.
    # Only exposes safe persisted metadata; no prompts, secrets, or raw payloads.
    class DetailPresenter
      # Whitelist of attribute names we are allowed to show (all persisted audit fields are safe by design)
      SAFE_KEYS = %w[
        id request_id endpoint merchant_id agent_key retriever_key composition_mode
        tool_used tool_names fallback_used memory_used summary_used
        parsed_entities parsed_intent_hints citations_count retrieved_sections_count
        latency_ms model_used success error_class error_message created_at
        followup_detected followup_type authorization_denied policy_reason_code
        tool_blocked_by_policy followup_inheritance_blocked corpus_version
        deterministic_explanation_used explanation_type explanation_key
        orchestration_used orchestration_step_count orchestration_halted_reason
        degraded failure_stage fallback_mode success_after_fallback
        execution_mode retrieval_skipped memory_skipped retrieval_budget_reduced
        invoked_skills skill_workflow_metadata
      ].freeze

      SECTION_GROUPS = {
        request: %w[id request_id endpoint created_at],
        context: %w[merchant_id agent_key retriever_key],
        parsing: %w[parsed_entities parsed_intent_hints followup_detected followup_type],
        execution_plan: %w[execution_mode retrieval_skipped memory_skipped retrieval_budget_reduced],
        tool_usage: %w[tool_used tool_names],
        orchestration: %w[orchestration_used orchestration_step_count orchestration_halted_reason],
        skills: %w[invoked_skills skill_workflow_metadata],
        retrieval: %w[retrieved_sections_count citations_count corpus_version],
        memory: %w[memory_used summary_used],
        composition: %w[composition_mode deterministic_explanation_used explanation_type explanation_key],
        policy: %w[authorization_denied tool_blocked_by_policy followup_inheritance_blocked policy_reason_code],
        resilience: %w[fallback_used degraded failure_stage fallback_mode success_after_fallback],
        timing: %w[latency_ms success error_class error_message model_used]
      }.freeze

      def self.call(audit)
        new(audit).call
      end

      def initialize(audit)
        @audit = audit
      end

      def call
        attrs = safe_attributes
        sections = SECTION_GROUPS.transform_values do |keys|
          keys.each_with_object({}) do |k, h|
            h[k] = format_value(attrs[k]) if attrs.key?(k)
          end.compact
        end
        path_summary = build_path_summary(attrs)
        {
          sections: sections,
          path_summary: path_summary,
          path_steps: build_path_steps(attrs)
        }
      end

      private

      def safe_attributes
        raw = @audit.attributes.slice(*SAFE_KEYS)
        raw.select { |_k, v| v.present? || v == false || v == true || v == 0 }
      end

      def format_value(val)
        return val if val.nil?
        return val if [true, false].include?(val)
        return val.to_s if val.is_a?(Time) || val.is_a?(ActiveSupport::TimeWithZone)
        return val if val.is_a?(Numeric)
        return val.inspect if val.is_a?(Hash) || val.is_a?(Array)
        val.to_s
      end

      def build_path_summary(attrs)
        mode = attrs['composition_mode'].presence || attrs['execution_mode'].presence
        parts = []
        parts << (mode || 'unknown')
        parts << 'degraded' if attrs['degraded'] || attrs['fallback_used']
        parts << 'non-streaming fallback' if attrs['fallback_mode'].to_s.include?('non_streaming')
        parts << 'policy blocked' if attrs['authorization_denied'] || attrs['tool_blocked_by_policy']
        parts.join(' · ')
      end

      def build_path_steps(attrs)
        steps = []
        steps << { label: 'Intent / parsing', value: (attrs['parsed_entities'].present? || attrs['parsed_intent_hints'].present?) ? 'Yes' : '—' }
        steps << { label: 'Orchestration used', value: attrs['orchestration_used'] ? 'Yes' : 'No' }
        steps << { label: 'Tool calls', value: attrs['tool_used'] ? (Array(attrs['tool_names']).join(', ') || 'Yes') : 'No' }
        steps << { label: 'Retrieval used', value: (attrs['retrieved_sections_count'].to_i.positive? || attrs['citations_count'].to_i.positive?) ? 'Yes' : 'No' }
        steps << { label: 'Memory used', value: attrs['memory_used'] ? 'Yes' : 'No' }
        steps << { label: 'Citations included', value: attrs['citations_count'].to_i.positive? ? attrs['citations_count'] : 'No' }
        steps << { label: 'Deterministic explanation', value: attrs['deterministic_explanation_used'] ? "#{attrs['explanation_type']} / #{attrs['explanation_key']}" : 'No' }
        inv = Array(attrs['invoked_skills'])
        steps << { label: 'Skills invoked', value: inv.any? ? inv.map { |s| (s['skill_key'] || s[:skill_key]).to_s }.join(', ') : 'No' }
        steps << { label: 'Fallback path', value: attrs['fallback_used'] ? 'Yes' : 'No' }
        steps
      end
    end
  end
end
