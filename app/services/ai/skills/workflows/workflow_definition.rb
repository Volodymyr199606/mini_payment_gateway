# frozen_string_literal: true

module Ai
  module Skills
    module Workflows
      # Explicit, immutable description of one allowed bounded workflow (no dynamic generation).
      class WorkflowDefinition
        MAX_SKILL_STEPS = 3

        attr_reader :key, :description, :max_steps, :allowed_routing_agents, :skill_steps,
                    :execution_agent_key, :phase

        # @param key [Symbol]
        # @param skill_steps [Array<Symbol>] ordered sequence (1..3)
        # @param execution_agent_key [Symbol, nil] Invoker agent; nil means use routing agent
        # @param phase [Symbol] :post_tool or :pre_composition
        def initialize(
          key:,
          description:,
          skill_steps:,
          allowed_routing_agents:,
          max_steps: nil,
          execution_agent_key: nil,
          phase: :post_tool
        )
          @key = key.to_sym
          @description = description.to_s
          @skill_steps = Array(skill_steps).map(&:to_sym)
          @allowed_routing_agents = Array(allowed_routing_agents).map(&:to_sym)
          @max_steps = (max_steps || @skill_steps.size).to_i
          @execution_agent_key = execution_agent_key&.to_sym
          @phase = phase.to_sym
          raise ArgumentError, 'workflow must have 1-3 steps' if @skill_steps.empty? || @skill_steps.size > MAX_SKILL_STEPS
          raise ArgumentError, 'max_steps exceeds skill_steps' if @max_steps < @skill_steps.size
        end
      end
    end
  end
end
