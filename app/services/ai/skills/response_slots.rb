# frozen_string_literal: true

module Ai
  module Skills
    # Structured slots for skill output. Each slot is a single contributor target.
    # Precedence: primary_explanation > supporting_analysis > docs_clarification > style_transform.
    module ResponseSlots
      # Slot mappings for skills **not** in `Registry` — reserved for future work, **not** v1 platform skills.
      RESERVED_NON_V1_SKILL_KEYS = %i[merchant_account_status_summary docs_citation_summarizer].freeze

      SLOT_NAMES = %i[
        primary_explanation
        supporting_analysis
        docs_clarification
        style_transform
        warnings
        next_steps
      ].freeze

      # Skill key → primary slot it fills when successful.
      SKILL_TO_SLOT = {
        payment_state_explainer: :primary_explanation,
        webhook_trace_explainer: :primary_explanation,
        ledger_period_summary: :primary_explanation,
        discrepancy_detector: :supporting_analysis,
        followup_rewriter: :style_transform,
        refund_eligibility_explainer: :supporting_analysis,
        authorization_vs_capture_explainer: :supporting_analysis,
        payment_failure_summary: :primary_explanation,
        webhook_retry_summary: :supporting_analysis,
        reporting_trend_summary: :supporting_analysis,
        reconciliation_action_summary: :next_steps,
        merchant_account_status_summary: :primary_explanation,
        docs_citation_summarizer: :docs_clarification
      }.freeze

      # When multiple skills both target :primary_explanation and are deterministic,
      # lower index wins (canonical single explanation path).
      CANONICAL_PRIMARY_ORDER = %i[
        payment_state_explainer
        webhook_trace_explainer
        ledger_period_summary
        merchant_account_status_summary
        payment_failure_summary
      ].freeze

      # Slots that must not override deterministic factual content.
      STYLE_ONLY_SLOTS = %i[style_transform].freeze

      # Slots that may add to but not replace primary_explanation.
      ADDITIVE_SLOTS = %i[supporting_analysis warnings next_steps docs_clarification].freeze

      class << self
        def slot_for(skill_key)
          SKILL_TO_SLOT[skill_key.to_sym]
        end

        def style_only?(slot)
          STYLE_ONLY_SLOTS.include?(slot&.to_sym)
        end

        def additive?(slot)
          ADDITIVE_SLOTS.include?(slot&.to_sym)
        end

        def canonical_primary_rank(skill_key)
          idx = CANONICAL_PRIMARY_ORDER.index(skill_key.to_sym)
          idx.nil? ? 999 : idx
        end
      end
    end
  end
end
