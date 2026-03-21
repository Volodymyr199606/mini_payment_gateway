# frozen_string_literal: true

module Ai
  module Skills
    # Abstract skill: bounded, explicit capability invoked with a context hash.
    # Subclasses must define DEFINITION (SkillDefinition) and implement #execute.
    #
    # Skills are not autonomous agents: no recursive planning, no spawning subagents.
    # Policy checks should wrap invocation (see Invoker).
    class BaseSkill
      class << self
        def definition
          const_get(:DEFINITION)
        rescue NameError
          raise NotImplementedError, "#{name} must define DEFINITION (SkillDefinition)"
        end
      end

      # @param context [Hash] May include :agent_key, :merchant_id, :message, :session_context, etc.
      # @return [SkillResult]
      def execute(context:)
        raise NotImplementedError, "#{self.class.name} must implement #execute(context:)"
      end

      protected

      def stub_skill_result(skill_key:, definition:, context:)
        SkillResult.success(
          skill_key: skill_key,
          data: { stub: true },
          explanation: 'Skill registered; execution pipeline not wired yet.',
          metadata: {
            'agent_key' => context[:agent_key].to_s,
            'merchant_id' => context[:merchant_id]
          }.compact,
          deterministic: definition.deterministic?,
          safe_for_composition: true
        )
      end
    end
  end
end
