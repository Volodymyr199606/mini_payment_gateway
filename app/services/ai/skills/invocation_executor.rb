# frozen_string_literal: true

module Ai
  module Skills
    # Executes a planned skill invocation and returns a structured InvocationResult.
    # Single invocation per call; no chaining. Policy-aware via Invoker.
    class InvocationExecutor
      class << self
        # @param planned [Hash] { skill_key:, reason_code: } from InvocationPlanner
        # @param context [InvocationContext]
        # @return [InvocationResult]
        def call(planned:, context:)
          skill_key = planned[:skill_key]
          reason_code = planned[:reason_code]
          phase = context.phase

          skill_context = context.to_skill_context
          skill_context[:request_id] = Thread.current[:ai_request_id] if Thread.current[:ai_request_id].present?

          result = Invoker.call(
            agent_key: context.agent_key,
            skill_key: skill_key,
            context: skill_context
          )

          InvocationResult.executed(
            skill_key: skill_key,
            phase: phase,
            reason_code: reason_code,
            skill_result: result
          )
        end
      end
    end
  end
end
