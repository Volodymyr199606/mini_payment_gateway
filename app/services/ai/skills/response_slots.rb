# frozen_string_literal: true

module Ai
  module Skills
    # Structured slots for skill output. Each slot is a single contributor target.
    # Precedence: primary_explanation > supporting_analysis > docs_clarification > style_transform.
    module ResponseSlots
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
        merchant_account_status_summary: :primary_explanation,
        webhook_retry_summary: :supporting_analysis
      }.freeze

      # Slots that must not override deterministic factual content.
      STYLE_ONLY_SLOTS = %i[style_transform].freeze

      # Slots that may add to but not replace primary_explanation.
      ADDITIVE_SLOTS = %i[supporting_analysis warnings next_steps].freeze

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
      end
    end
  end
end
