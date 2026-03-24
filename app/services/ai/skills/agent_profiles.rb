# frozen_string_literal: true

module Ai
  module Skills
    # Registry of per-agent skill profiles. Single source for tuning.
    module AgentProfiles
      PROFILES = {
        support_faq: AgentProfile.new(
          agent_key: :support_faq,
          allowed_skill_keys: %i[
            docs_lookup payment_state_explainer followup_rewriter
            refund_eligibility_explainer authorization_vs_capture_explainer payment_failure_summary
          ],
          preferred_skill_keys: %i[payment_state_explainer payment_failure_summary followup_rewriter],
          suppressed_skill_keys: [],
          max_skills_per_request: 2,
          max_heavy_skills_per_request: 0,
          preferred_phases: %i[post_tool pre_composition],
          performance_sensitivity: :medium
        ),
        security_compliance: AgentProfile.new(
          agent_key: :security_compliance,
          allowed_skill_keys: %i[docs_lookup payment_state_explainer authorization_vs_capture_explainer],
          preferred_skill_keys: %i[authorization_vs_capture_explainer docs_lookup],
          suppressed_skill_keys: [],
          max_skills_per_request: 1,
          max_heavy_skills_per_request: 0,
          preferred_phases: %i[post_tool],
          performance_sensitivity: :high
        ),
        developer_onboarding: AgentProfile.new(
          agent_key: :developer_onboarding,
          allowed_skill_keys: %i[docs_lookup followup_rewriter authorization_vs_capture_explainer],
          preferred_skill_keys: %i[authorization_vs_capture_explainer docs_lookup followup_rewriter],
          suppressed_skill_keys: [],
          max_skills_per_request: 1,
          max_heavy_skills_per_request: 0,
          preferred_phases: %i[post_tool pre_composition],
          performance_sensitivity: :medium
        ),
        operational: AgentProfile.new(
          agent_key: :operational,
          allowed_skill_keys: %i[
            webhook_trace_explainer payment_state_explainer payment_failure_summary webhook_retry_summary
          ],
          preferred_skill_keys: %i[payment_state_explainer webhook_trace_explainer payment_failure_summary webhook_retry_summary],
          suppressed_skill_keys: [],
          max_skills_per_request: 2,
          max_heavy_skills_per_request: 0,
          preferred_phases: %i[post_tool],
          performance_sensitivity: :medium
        ),
        reconciliation_analyst: AgentProfile.new(
          agent_key: :reconciliation_analyst,
          allowed_skill_keys: %i[
            ledger_period_summary discrepancy_detector payment_state_explainer transaction_trace
            refund_eligibility_explainer authorization_vs_capture_explainer
            reporting_trend_summary reconciliation_action_summary
          ],
          preferred_skill_keys: %i[ledger_period_summary discrepancy_detector reconciliation_action_summary],
          suppressed_skill_keys: %i[reporting_trend_summary],
          max_skills_per_request: 2,
          max_heavy_skills_per_request: 1,
          preferred_phases: %i[post_tool],
          performance_sensitivity: :high
        ),
        reporting_calculation: AgentProfile.new(
          agent_key: :reporting_calculation,
          allowed_skill_keys: %i[ledger_period_summary time_range_resolution report_explainer reporting_trend_summary],
          preferred_skill_keys: %i[ledger_period_summary report_explainer],
          suppressed_skill_keys: %i[reporting_trend_summary],
          max_skills_per_request: 1,
          max_heavy_skills_per_request: 0,
          preferred_phases: %i[post_tool],
          performance_sensitivity: :high
        )
      }.freeze

      class << self
        def for(agent_key)
          key = agent_key.to_sym
          PROFILES[key] || build_fallback(key)
        end

        def all
          PROFILES.values
        end

        private

        def build_fallback(agent_key)
          defn = AgentRegistry.definition(agent_key)
          AgentProfile.new(
            agent_key: agent_key,
            allowed_skill_keys: defn&.allowed_skill_keys || [],
            preferred_skill_keys: defn&.allowed_skill_keys || [],
            suppressed_skill_keys: [],
            max_skills_per_request: defn&.max_skills_per_request || 2,
            max_heavy_skills_per_request: 1,
            preferred_phases: %i[post_tool],
            performance_sensitivity: :medium
          )
        end
      end
    end
  end
end
