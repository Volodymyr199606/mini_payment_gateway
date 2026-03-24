# frozen_string_literal: true

module Ai
  module Skills
    module Workflows
      # Runs a registered workflow as an ordered sequence of skill invocations.
      # Does not call Selector or Registry from inside steps — no nested workflows.
      class Executor
        REASON = 'bounded_workflow_step'

        class << self
          # @return [Hash] same keys as InvocationCoordinator.post_tool plus :workflow_result
          def run_post_tool(workflow_def:, context:, run_result:, routing_agent_key:)
            BaseWorkflow.with_execution_guard do
              raise ArgumentError, 'wrong phase' unless workflow_def.phase == :post_tool
              raise ArgumentError, 'wrong context phase' unless context.phase == :post_tool

              t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              invoker_agent = workflow_def.execution_agent_key || InvocationCoordinator.resolve_skill_agent(routing_agent_key, context.tool_names)

              wf_ctx = build_post_tool_context(invoker_agent, context, run_result)

              invocation_results = []
              contributing = []
              skipped = []
              stop_reason = 'completed'
              attempted = 0
              completed = 0

              workflow_def.skill_steps.each_with_index do |skill_key, idx|
                break if idx >= workflow_def.max_steps
                break if idx >= WorkflowDefinition::MAX_SKILL_STEPS

                if optional_skip?(workflow_def, skill_key, wf_ctx)
                  skipped << skill_key.to_s
                  next
                end

                attempted += 1
                planned = { skill_key: skill_key, reason_code: REASON }
                inv_result = InvocationExecutor.call(planned: planned, context: wf_ctx)
                invocation_results << inv_result.to_audit_hash
                InvocationCoordinator.log_skill_invocation(inv_result, wf_ctx)

                if inv_result.invoked && inv_result.success
                  contributing << skill_key.to_s
                  completed += 1
                elsif inv_result.invoked && !inv_result.success
                  stop_reason = 'skill_execution_failed'
                  break
                else
                  stop_reason = 'skill_execution_failed'
                  break
                end
              end

              base_reply = run_result.reply_text
              composition = CompositionPlanner.plan(
                reply_text: base_reply,
                invocation_results: invocation_results,
                agent_key: invoker_agent,
                tool_names: context.tool_names,
                orchestration_step_count: run_result&.step_count
              )
              skill_affected = invocation_results.any? { |r| r[:invoked] && r[:success] }
              elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round

              wf_result = WorkflowResult.new(
                workflow_key: workflow_def.key,
                workflow_selected: true,
                steps_attempted: attempted,
                steps_completed: completed,
                contributing_skills: contributing,
                skipped_skills: skipped,
                stop_reason: stop_reason,
                success: stop_reason == 'completed' || completed.positive?,
                affected_final_response: skill_affected,
                metadata: { 'routing_agent' => routing_agent_key.to_s, 'invoker_agent' => invoker_agent.to_s },
                duration_ms: elapsed_ms
              )

              {
                reply_text: composition.reply_text,
                invocation_results: invocation_results,
                skill_affected_reply: skill_affected,
                composition_result: composition,
                workflow_result: wf_result
              }
            end
          end

          # @return [Hash, nil] extends try_pre_composition_rewrite shape
          def attach_rewrite_metadata(invocation_results:, routing_agent_key:, duration_ms: nil)
            return nil unless Selector.workflows_enabled?

            defn = Registry.fetch(:rewrite_response_workflow)
            return nil unless defn

            contributing = invocation_results.select { |r| r[:invoked] && r[:success] }.map { |r| r[:skill_key].to_s }
            WorkflowResult.new(
              workflow_key: defn.key,
              workflow_selected: true,
              steps_attempted: invocation_results.size,
              steps_completed: contributing.size,
              contributing_skills: contributing,
              stop_reason: contributing.any? ? 'completed' : 'skill_execution_failed',
              success: contributing.any?,
              affected_final_response: contributing.any?,
              metadata: { 'routing_agent' => routing_agent_key.to_s },
              duration_ms: duration_ms
            )
          end

          private

          def build_post_tool_context(invoker_agent, context, run_result)
            InvocationContext.for_post_tool(
              agent_key: invoker_agent,
              merchant_id: context.merchant_id,
              message: context.message,
              tool_names: context.tool_names,
              deterministic_data: run_result&.deterministic_data || {},
              run_result: run_result,
              intent: context.intent
            )
          end

          def optional_skip?(workflow_def, skill_key, context)
            if workflow_def.key == :webhook_failure_analysis_workflow && skill_key == :payment_failure_summary
              return true unless context.has_payment_failure_data? || context.has_webhook_retry_relevant_state?
            end

            false
          end
        end
      end
    end
  end
end
