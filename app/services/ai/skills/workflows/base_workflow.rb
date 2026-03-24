# frozen_string_literal: true

module Ai
  module Skills
    module Workflows
      # Shared helpers for bounded workflows (no orchestration logic — Executor owns execution).
      module BaseWorkflow
        module_function

        def with_execution_guard
          raise Ai::Skills::Workflows::NestedWorkflowError, 'nested workflow not allowed' if Thread.current[:ai_workflow_executing]

          Thread.current[:ai_workflow_executing] = true
          yield
        ensure
          Thread.current[:ai_workflow_executing] = nil
        end
      end

      class NestedWorkflowError < StandardError; end
    end
  end
end
