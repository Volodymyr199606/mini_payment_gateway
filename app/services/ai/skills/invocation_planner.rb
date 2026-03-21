# frozen_string_literal: true

module Ai
  module Skills
    # Rule-based planning for skill invocation. No recursion, no chaining.
    # Decides which allowed skill (if any) to run at each phase. Bounded and auditable.
    class InvocationPlanner
      MAX_INVOCATIONS_PER_REQUEST = 2
      INVOCATIONS_PER_PHASE = 1

      PHASE_SKILL_RULES = {
        pre_composition: %i[followup_rewriter],
        post_tool: %i[payment_state_explainer webhook_trace_explainer ledger_period_summary discrepancy_detector]
      }.freeze

      class << self
        # @param context [InvocationContext]
        # @param already_invoked [Array<Symbol>] skills invoked earlier this request
        # @return [Hash, nil] { skill_key:, reason_code: } or nil if no skill to invoke
        def plan(context:, already_invoked: [])
          return nil if already_invoked.size >= MAX_INVOCATIONS_PER_REQUEST

          rules = PHASE_SKILL_RULES[context.phase]
          return nil unless rules.present?

          rules.each do |skill_key|
            next if already_invoked.include?(skill_key)

            reason = should_invoke?(context, skill_key)
            next unless reason

            return { skill_key: skill_key, reason_code: reason }
          end
          nil
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

        def should_invoke?(context, skill_key)
          return nil unless agent_allows?(context.agent_key, skill_key)

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
      end
    end
  end
end
