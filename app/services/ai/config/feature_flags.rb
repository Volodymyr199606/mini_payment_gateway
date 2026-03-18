# frozen_string_literal: true

module Ai
  module Config
    # Centralized AI feature flags and rollout toggles. Single source of truth for ENV-driven flags.
    # Use these accessors instead of reading ENV directly so behavior is consistent and testable.
    module FeatureFlags
      ENV_TRUE = %w[true 1].freeze

      class << self
        def ai_enabled?
          env_bool('AI_ENABLED', default: true)
        end

        def ai_streaming_enabled?
          env_bool('AI_STREAMING_ENABLED', default: false)
        end

        def ai_debug_enabled?
          env_bool('AI_DEBUG', default: false)
        end

        def ai_graph_retrieval_enabled?
          env_bool('AI_CONTEXT_GRAPH_ENABLED', default: false)
        end

        def ai_vector_retrieval_enabled?
          env_bool('AI_VECTOR_RAG_ENABLED', default: false)
        end

        def ai_orchestration_enabled?
          env_bool('AI_ORCHESTRATION_ENABLED', default: true)
        end

        def ai_cache_bypass?
          env_bool('AI_CACHE_BYPASS', default: false)
        end

        # Internal/dev-only tooling: playground, analytics, health, audits, replay.
        # In production these are disabled unless AI_INTERNAL_TOOLING_ALLOWED=true (explicit allow).
        def ai_playground_enabled?
          internal_tooling_available?
        end

        def ai_analytics_enabled?
          internal_tooling_available?
        end

        def ai_health_enabled?
          internal_tooling_available?
        end

        def ai_audits_enabled?
          internal_tooling_available?
        end

        def ai_replay_enabled?
          internal_tooling_available?
        end

        # True when dev/test OR production with explicit AI_INTERNAL_TOOLING_ALLOWED=true.
        def internal_tooling_available?
          return true if Rails.env.development? || Rails.env.test?
          env_bool('AI_INTERNAL_TOOLING_ALLOWED', default: false)
        end

        def deterministic_explanations_enabled?
          env_bool('AI_DETERMINISTIC_EXPLANATIONS_ENABLED', default: true)
        end

        # Safe summary of active flags for internal tooling/observability (no secrets).
        def safe_summary
          {
            ai_enabled: ai_enabled?,
            ai_streaming_enabled: ai_streaming_enabled?,
            ai_debug_enabled: ai_debug_enabled?,
            ai_graph_retrieval_enabled: ai_graph_retrieval_enabled?,
            ai_vector_retrieval_enabled: ai_vector_retrieval_enabled?,
            ai_orchestration_enabled: ai_orchestration_enabled?,
            ai_cache_bypass: ai_cache_bypass?,
            internal_tooling_available: internal_tooling_available?,
            deterministic_explanations_enabled: deterministic_explanations_enabled?
          }.freeze
        end

        private

        def env_bool(key, default: false)
          v = ENV[key].to_s.strip.downcase
          return default if v.blank?
          v.in?(ENV_TRUE)
        end
      end
    end
  end
end
