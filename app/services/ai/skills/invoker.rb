# frozen_string_literal: true

module Ai
  module Skills
    # Bounded skill invocation: one skill, one result, no chaining. Policy-friendly entry point.
    class Invoker
      class SkillNotAllowedError < StandardError; end

      class << self
        # @param agent_key [Symbol] Routing agent key
        # @param skill_key [Symbol]
        # @param context [Hash] Passed to skill; may include :merchant_id, :message, :request_id
        # @return [SkillResult]
        def call(agent_key:, skill_key:, context: {})
          agent_key = agent_key.to_sym
          skill_key = skill_key.to_sym

          unless Registry.known?(skill_key)
            return SkillResult.failure(
              skill_key: skill_key,
              error_code: 'unknown_skill',
              error_message: 'Skill is not registered.',
              metadata: { 'agent_key' => agent_key.to_s }
            )
          end

          agent_def = AgentRegistry.definition(agent_key)
          unless agent_def&.allowed_skill?(skill_key)
            return SkillResult.failure(
              skill_key: skill_key,
              error_code: 'skill_not_allowed', # safe: no cross-tenant data
              error_message: 'This agent is not allowed to use this skill.',
              metadata: { 'agent_key' => agent_key.to_s },
              deterministic: true
            )
          end

          ctx = context.merge(agent_key: agent_key, skill_key: skill_key)
          klass = Registry.fetch(skill_key)
          klass.new.execute(context: ctx)
        rescue StandardError => e
          Rails.logger.error(
            event: 'ai_skill_invocation_error',
            skill_key: skill_key,
            agent_key: agent_key,
            error_class: e.class.name,
            message: e.message
          )
          SkillResult.failure(
            skill_key: skill_key,
            error_code: 'skill_execution_error',
            error_message: 'Skill execution failed.',
            metadata: { 'agent_key' => agent_key.to_s },
            deterministic: false
          )
        end
      end
    end
  end
end
