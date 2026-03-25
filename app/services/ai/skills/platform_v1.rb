# frozen_string_literal: true

module Ai
  module Skills
    # Official **v1 bounded skill platform** boundary: version labels, supported extension surface,
    # and boot-time validation (development/test) so registries, profiles, and workflows do not drift.
    #
    # Not a second registry — `Registry`, `AgentProfiles`, and `Workflows::Registry` remain canonical.
    # This module documents and enforces alignment for the stable internal platform.
    module PlatformV1
      # Human-facing platform label (bump on intentional breaking contract changes).
      VERSION = '1.0.0'

      # Serialized contract family for SkillResult / composition / workflow audit hashes (bump only with migration plan).
      CONTRACT_SCHEMA_VERSION = '1.0.0'

      # Supported invocation phases (must match `InvocationContext::PHASES`).
      INVOCATION_PHASES = %i[pre_retrieval pre_tool post_tool pre_composition].freeze

      # Explicitly **not** part of v1 (see docs/AI_SKILL_PLATFORM_V1.md).
      OUT_OF_SCOPE = [
        :autonomous_subagents,
        :recursive_planning,
        :dynamic_workflow_generation,
        :arbitrary_skill_chaining,
        :nested_workflows,
        :runtime_skill_discovery
      ].freeze

      class << self
        # Sorted keys from `Registry::SKILLS` — official v1 skill set.
        def official_skill_keys
          Registry::SKILLS.keys.map(&:to_sym).sort
        end

        # Sorted keys from `Workflows::Registry` — official v1 workflows only.
        def official_workflow_keys
          Workflows::Registry.keys.map(&:to_sym).sort
        end

        # Fail-fast checks: registry, workflows, agent/profile alignment, response-slot coverage.
        # Runs from `config/initializers/ai_registries.rb` in development/test.
        def validate!
          return true unless Rails.env.development? || Rails.env.test?

          Registry.validate!
          Workflows::Registry.validate!

          validate_agent_profiles_vs_definitions!
          validate_workflow_definitions!
          validate_response_slots_cover_registry!
          validate_contract_schema_versions!

          true
        end

        private

        def validate_contract_schema_versions!
          unless SkillResult::CONTRACT_SCHEMA_VERSION == CONTRACT_SCHEMA_VERSION &&
                 CompositionResult::CONTRACT_SCHEMA_VERSION == CONTRACT_SCHEMA_VERSION &&
                 Workflows::WorkflowResult::CONTRACT_SCHEMA_VERSION == CONTRACT_SCHEMA_VERSION
            raise ArgumentError,
                  'PlatformV1: CONTRACT_SCHEMA_VERSION mismatch between PlatformV1 and SkillResult / ' \
                  'CompositionResult / WorkflowResult — bump together with docs/migration note.'
          end
        end

        def validate_agent_profiles_vs_definitions!
          AgentProfiles::PROFILES.each do |agent_key, profile|
            defn = AgentRegistry.definition(agent_key)
            raise ArgumentError, "PlatformV1: missing AgentDefinition for #{agent_key.inspect}" unless defn

            p_allowed = profile.allowed_skill_keys.sort
            d_allowed = defn.allowed_skill_keys.sort
            if p_allowed != d_allowed
              raise ArgumentError,
                    "PlatformV1: AgentProfiles vs AgentDefinition allowed_skill_keys mismatch for #{agent_key}: " \
                    "#{p_allowed.inspect} != #{d_allowed.inspect}"
            end

            if profile.max_skills_per_request > defn.max_skills_per_request
              raise ArgumentError,
                    "PlatformV1: profile max_skills_per_request (#{profile.max_skills_per_request}) exceeds " \
                    "AgentDefinition (#{defn.max_skills_per_request}) for #{agent_key}"
            end

            profile.allowed_skill_keys.each do |sk|
              next if Registry.known?(sk)

              raise ArgumentError, "PlatformV1: profile #{agent_key} references unknown skill #{sk.inspect}"
            end
          end
        end

        def validate_workflow_definitions!
          Workflows::Registry.definitions.each do |wk, wdef|
            wdef.skill_steps.each do |step|
              unless Registry.known?(step)
                raise ArgumentError, "PlatformV1: workflow #{wk} references unknown skill #{step.inspect}"
              end
            end

            wdef.allowed_routing_agents.each do |ak|
              unless AgentRegistry::REGISTRY.key?(ak)
                raise ArgumentError, "PlatformV1: workflow #{wk} references unknown agent #{ak.inspect}"
              end
            end
          end
        end

        def validate_response_slots_cover_registry!
          Registry.all_keys.each do |sk|
            slot = ResponseSlots.slot_for(sk)
            raise ArgumentError, "PlatformV1: ResponseSlots missing mapping for registered skill #{sk.inspect}" if slot.nil?
          end
        end
      end
    end
  end
end
