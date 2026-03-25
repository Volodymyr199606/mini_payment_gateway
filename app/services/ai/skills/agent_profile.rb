# frozen_string_literal: true

module Ai
  module Skills
    # Per-agent skill profile: preferred skills, budgets, and performance tuning.
    # Read-only; used by InvocationPlanner and analytics. v1 platform profiles are frozen in `AgentProfiles`
    # and validated against `AgentDefinition` via `Ai::Skills::PlatformV1.validate!`.
    class AgentProfile
      attr_reader :agent_key, :allowed_skill_keys, :preferred_skill_keys,
                  :suppressed_skill_keys, :max_skills_per_request,
                  :max_heavy_skills_per_request, :preferred_phases,
                  :performance_sensitivity

      def initialize(
        agent_key:,
        allowed_skill_keys: [],
        preferred_skill_keys: [],
        suppressed_skill_keys: [],
        max_skills_per_request: 2,
        max_heavy_skills_per_request: 1,
        preferred_phases: %i[post_tool],
        performance_sensitivity: :medium
      )
        @agent_key = agent_key.to_sym
        @allowed_skill_keys = Array(allowed_skill_keys).map(&:to_sym).freeze
        @preferred_skill_keys = Array(preferred_skill_keys).map(&:to_sym).freeze
        @suppressed_skill_keys = Array(suppressed_skill_keys).map(&:to_sym).freeze
        @max_skills_per_request = [max_skills_per_request.to_i, 1].max
        @max_heavy_skills_per_request = max_heavy_skills_per_request.to_i
        @preferred_phases = Array(preferred_phases).map(&:to_sym).freeze
        @performance_sensitivity = performance_sensitivity.to_sym
      end

      def allows?(skill_key)
        @allowed_skill_keys.include?(skill_key.to_sym)
      end

      def preferred?(skill_key)
        @preferred_skill_keys.include?(skill_key.to_sym)
      end

      def suppressed?(skill_key)
        @suppressed_skill_keys.include?(skill_key.to_sym)
      end

      def preference_rank(skill_key)
        idx = @preferred_skill_keys.index(skill_key.to_sym)
        idx.nil? ? 999 : idx
      end

      def budget_reached?(already_invoked:)
        already_invoked.size >= @max_skills_per_request
      end

      def heavy_budget_reached?(already_invoked:)
        return false if @max_heavy_skills_per_request <= 0

        SkillWeights.heavy_skills_count(already_invoked) >= @max_heavy_skills_per_request
      end

      def performance_sensitive?
        @performance_sensitivity == :high
      end

      def to_h
        {
          agent_key: @agent_key,
          max_skills_per_request: @max_skills_per_request,
          max_heavy_skills_per_request: @max_heavy_skills_per_request,
          performance_sensitivity: @performance_sensitivity
        }
      end
    end
  end
end
