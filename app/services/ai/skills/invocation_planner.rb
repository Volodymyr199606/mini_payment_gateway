# frozen_string_literal: true

module Ai
  module Skills
    # Rule-based planning for skill invocation. No recursion, no chaining.
    # Decides which allowed skill (if any) to run at each phase. Bounded and auditable.
    # Uses AgentProfiles for per-agent budgets, preferred order, and suppression.
    class InvocationPlanner
      MAX_INVOCATIONS_PER_REQUEST = 2
      INVOCATIONS_PER_PHASE = 1

      # All four phases supported; pre_retrieval/pre_tool have no skills yet (extensible).
      PHASE_SKILL_RULES = {
        pre_retrieval: [],
        pre_tool: [],
        post_tool: %i[
          payment_state_explainer webhook_trace_explainer ledger_period_summary discrepancy_detector
          refund_eligibility_explainer authorization_vs_capture_explainer
          payment_failure_summary webhook_retry_summary reporting_trend_summary reconciliation_action_summary
        ],
        pre_composition: %i[followup_rewriter]
      }.freeze

      SUPPRESSION_REASONS = {
        budget_reached: 'profile_budget_reached',
        heavy_budget_reached: 'profile_heavy_budget_reached',
        not_preferred_suppressed: 'profile_suppressed_skill',
        threshold_not_met: 'invocation_threshold_not_met'
      }.freeze

      class << self
        # @param context [InvocationContext]
        # @param already_invoked [Array<Symbol>] skills invoked earlier this request
        # @return [Hash, nil] { skill_key:, reason_code: } or nil if no skill to invoke
        def plan(context:, already_invoked: [])
          profile = AgentProfiles.for(context.agent_key)
          max_allowed = [profile.max_skills_per_request, MAX_INVOCATIONS_PER_REQUEST].min

          return nil if already_invoked.size >= max_allowed

          rules = ordered_skills_for_phase(context.phase, profile)
          return nil unless rules.present?

          rules.each do |skill_key|
            next if already_invoked.include?(skill_key)

            reason = should_invoke?(context, skill_key, already_invoked: already_invoked, profile: profile)
            next unless reason

            return { skill_key: skill_key, reason_code: reason }
          end
          nil
        end

        # Order phase skills by profile preference (preferred first, then by PHASE_SKILL_RULES order).
        def ordered_skills_for_phase(phase, profile)
          base = PHASE_SKILL_RULES[phase.to_sym] || []
          return base if base.empty?

          preferred = profile.preferred_skill_keys & base
          others = base - preferred
          (preferred + others).uniq
        end

        # @return [Array<Hash>] all planned invocations for the request (for debugging)
        def plan_all_for_request(context:, phase:)
          ctx = context.is_a?(InvocationContext) ? context : InvocationContext.new(phase: phase, **context)
          result = []
          invoked = []
          loop do
            planned = plan(context: ctx, already_invoked: invoked)
            break unless planned

            result << planned
            invoked << planned[:skill_key]
          end
          result
        end

        private

        def should_invoke?(context, skill_key, already_invoked: [], profile: nil)
          profile ||= AgentProfiles.for(context.agent_key)
          return nil unless agent_allows?(context.agent_key, skill_key)
          return nil if profile.budget_reached?(already_invoked: already_invoked)
          return nil if SkillWeights.heavy?(skill_key) && profile.heavy_budget_reached?(already_invoked: already_invoked)

          case skill_key
          when :followup_rewriter
            rule_followup_rewriter(context)
          when :payment_state_explainer
            rule_payment_state_explainer(context)
          when :webhook_trace_explainer
            rule_webhook_trace_explainer(context)
          when :ledger_period_summary
            rule_ledger_period_summary(context)
          when :discrepancy_detector
            rule_discrepancy_detector(context)
          when :refund_eligibility_explainer
            rule_refund_eligibility_explainer(context, already_invoked: already_invoked)
          when :authorization_vs_capture_explainer
            rule_authorization_vs_capture_explainer(context, already_invoked: already_invoked)
          when :payment_failure_summary
            rule_payment_failure_summary(context)
          when :webhook_retry_summary
            rule_webhook_retry_summary(context, profile: profile)
          when :reporting_trend_summary
            rule_reporting_trend_summary(context, profile: profile)
          when :reconciliation_action_summary
            rule_reconciliation_action_summary(context)
          else
            nil
          end
        end

        def agent_allows?(agent_key, skill_key)
          defn = AgentRegistry.definition(agent_key)
          defn&.allowed_skill?(skill_key)
        end

        def rule_followup_rewriter(context)
          return nil unless context.phase == :pre_composition
          return nil unless context.concise_rewrite_mode?
          return nil unless context.followup_rewrite?
          return nil unless context.prior_assistant_content.present?

          'concise_rewrite_with_prior'
        end

        def rule_payment_state_explainer(context)
          return nil unless context.phase == :post_tool
          return nil unless context.has_payment_data?

          'payment_data_retrieved'
        end

        def rule_webhook_trace_explainer(context)
          return nil unless context.phase == :post_tool
          return nil unless context.has_webhook_data?

          'webhook_data_retrieved'
        end

        def rule_ledger_period_summary(context)
          return nil unless context.phase == :post_tool
          return nil unless context.has_ledger_data?

          'ledger_data_retrieved'
        end

        def rule_discrepancy_detector(context)
          return nil unless context.phase == :post_tool
          return nil unless context.has_ledger_data?

          'ledger_data_for_reconciliation'
        end

        def rule_refund_eligibility_explainer(context, already_invoked:)
          return nil unless context.phase == :post_tool
          return nil unless already_invoked.include?(:payment_state_explainer)
          return nil unless context.has_payment_intent_data?
          return nil unless context.captured_payment_intent_with_refund_context?
          return nil if context.authorization_vs_capture_message?
          return nil unless context.refund_eligibility_message?

          'refund_eligibility_context'
        end

        def rule_authorization_vs_capture_explainer(context, already_invoked:)
          return nil unless context.phase == :post_tool
          return nil unless already_invoked.include?(:payment_state_explainer)
          return nil unless context.has_payment_intent_data?
          return nil unless context.authorization_vs_capture_message?

          'auth_capture_clarification'
        end

        def rule_payment_failure_summary(context)
          return nil unless context.phase == :post_tool
          return nil unless context.has_payment_failure_data?

          'payment_failure_detected'
        end

        def rule_webhook_retry_summary(context, profile: nil)
          return nil unless context.phase == :post_tool
          return nil unless context.has_webhook_data?
          return nil unless context.has_webhook_retry_relevant_state?

          'webhook_retry_status'
        end

        def rule_reporting_trend_summary(context, profile: nil)
          return nil unless context.phase == :post_tool
          return nil unless context.has_ledger_data?
          return nil if profile&.suppressed?(:reporting_trend_summary) && !context.has_trend_context?

          'ledger_data_for_trends'
        end

        def rule_reconciliation_action_summary(context)
          return nil unless context.phase == :post_tool
          return nil unless context.has_ledger_data?

          'ledger_data_for_reconciliation_actions'
        end
      end
    end
  end
end
