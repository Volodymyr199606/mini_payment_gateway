# frozen_string_literal: true

module Ai
  module Skills
    # Performance classification for skills. Used for profile budgets and suppression.
    # light: fast, minimal I/O (e.g. payment_state from cached template)
    # medium: moderate work (e.g. ledger summary, webhook trace)
    # heavy: multiple calls, comparison logic (e.g. reporting_trend, discrepancy_detector)
    module SkillWeights
      LIGHT = :light
      MEDIUM = :medium
      HEAVY = :heavy

      WEIGHTS = {
        payment_state_explainer: LIGHT,
        authorization_vs_capture_explainer: LIGHT,
        refund_eligibility_explainer: LIGHT,
        payment_failure_summary: LIGHT,
        webhook_trace_explainer: LIGHT,
        webhook_retry_summary: LIGHT,
        followup_rewriter: LIGHT,
        docs_lookup: LIGHT,
        ledger_period_summary: MEDIUM,
        report_explainer: MEDIUM,
        time_range_resolution: LIGHT,
        transaction_trace: MEDIUM,
        discrepancy_detector: HEAVY,
        reporting_trend_summary: HEAVY,
        reconciliation_action_summary: MEDIUM,
        failure_summary: MEDIUM,
        merchant_account_status_summary: LIGHT,
        docs_citation_summarizer: MEDIUM
      }.freeze

      class << self
        def weight(skill_key)
          WEIGHTS[skill_key.to_sym] || MEDIUM
        end

        def light?(skill_key)
          weight(skill_key) == LIGHT
        end

        def heavy?(skill_key)
          weight(skill_key) == HEAVY
        end

        def medium?(skill_key)
          weight(skill_key) == MEDIUM
        end

        def heavy_skills_count(skill_keys)
          Array(skill_keys).count { |k| heavy?(k) }
        end
      end
    end
  end
end
