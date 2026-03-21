# frozen_string_literal: true

module Ai
  module Skills
    # Coordinates skill invocation at specific pipeline phases.
    # Returns structured results for composition and audit. Bounded; no recursion.
    class InvocationCoordinator
      class << self
        # Post-tool: optionally invoke a skill when orchestration returned tool data.
        # @return [Hash] { reply_text:, invocation_results:, skill_affected_reply: }
        def post_tool(
          agent_key:,
          merchant_id:,
          message:,
          tool_names:,
          deterministic_data:,
          run_result:,
          intent: nil
        )
          skill_agent = resolve_skill_agent(agent_key, tool_names)
          context = InvocationContext.for_post_tool(
            agent_key: skill_agent,
            merchant_id: merchant_id,
            message: message,
            tool_names: tool_names,
            deterministic_data: deterministic_data,
            run_result: run_result,
            intent: intent
          )

          invocation_results = []
          reply_text = run_result.reply_text

          planned = InvocationPlanner.plan(context: context, already_invoked: [])
          if planned
            inv_result = InvocationExecutor.call(planned: planned, context: context)
            invocation_results << inv_result.to_audit_hash
            log_skill_invocation(inv_result, context)

            # Only replace reply when single-step; multi-step runner reply already combines both
            if inv_result.invoked && inv_result.success && inv_result.explanation.present? && tool_names.size <= 1
              reply_text = inv_result.explanation
            end
          end

          {
            reply_text: reply_text,
            invocation_results: invocation_results,
            skill_affected_reply: invocation_results.any? { |r| r[:invoked] && r[:success] }
          }
        end

        # Pre-composition: try followup_rewriter for concise_rewrite path.
        # @return [Hash, nil] { reply_text:, invocation_results: } if skill handled, else nil
        def try_pre_composition_rewrite(
          agent_key:,
          merchant_id:,
          message:,
          followup:,
          prior_assistant_content:,
          execution_plan:
        )
          return nil unless execution_plan.execution_mode == :concise_rewrite_only
          return nil unless prior_assistant_content.present?

          context = InvocationContext.for_pre_composition(
            agent_key: agent_key,
            merchant_id: merchant_id,
            message: message,
            followup: followup,
            prior_assistant_content: prior_assistant_content,
            execution_plan: execution_plan
          )

          planned = InvocationPlanner.plan(context: context, already_invoked: [])
          return nil unless planned

          inv_result = InvocationExecutor.call(planned: planned, context: context)
          log_skill_invocation(inv_result, context)

          if inv_result.invoked && inv_result.success && inv_result.explanation.present?
            {
              reply_text: inv_result.explanation,
              invocation_results: [inv_result.to_audit_hash]
            }
          else
            nil
          end
        end

        def log_skill_invocation(inv_result, context)
          return unless inv_result.respond_to?(:to_audit_hash)
          h = inv_result.to_audit_hash
          ::Ai::Observability::EventLogger.log_skill_invocation(
            request_id: Thread.current[:ai_request_id],
            skill_key: h[:skill_key],
            agent_key: context&.agent_key,
            phase: h[:phase],
            invoked: h[:invoked],
            success: h[:success],
            reason_code: h[:reason_code],
            affected_final_response: h[:invoked] && h[:success]
          )
        end

        def resolve_skill_agent(agent_key, tool_names)
          primary = tool_names.first.to_s
          case primary
          when 'get_webhook_event' then :operational
          when 'get_ledger_summary' then :reporting_calculation
          else agent_key.to_sym
          end
        end
      end
    end
  end
end
