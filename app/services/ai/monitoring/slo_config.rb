# frozen_string_literal: true

module Ai
  module Monitoring
    # Configurable SLO thresholds. Read from ENV with conservative defaults.
    # Example ENV: AI_SLO_P95_MS=8000, AI_SLO_ERROR_RATE_MAX=0.05
    class SloConfig
      DEFAULTS = {
        p95_latency_ms: 12_000,
        error_rate_max: 0.08,
        degraded_fallback_rate_max: 0.15,
        retrieval_failure_rate_max: 0.20,
        policy_blocked_rate_warn: 0.10,
        citation_reask_rate_warn: 0.25,
        orchestration_failure_rate_max: 0.15
      }.freeze

      ENV_KEYS = {
        p95_latency_ms: 'AI_SLO_P95_MS',
        error_rate_max: 'AI_SLO_ERROR_RATE_MAX',
        degraded_fallback_rate_max: 'AI_SLO_DEGRADED_RATE_MAX',
        retrieval_failure_rate_max: 'AI_SLO_RETRIEVAL_FAILURE_RATE_MAX',
        policy_blocked_rate_warn: 'AI_SLO_POLICY_BLOCKED_WARN',
        citation_reask_rate_warn: 'AI_SLO_CITATION_REASK_WARN',
        orchestration_failure_rate_max: 'AI_SLO_ORCHESTRATION_FAILURE_RATE_MAX'
      }.freeze

      class << self
        def p95_latency_ms
          integer_from_env(ENV_KEYS[:p95_latency_ms], DEFAULTS[:p95_latency_ms])
        end

        def error_rate_max
          float_from_env(ENV_KEYS[:error_rate_max], DEFAULTS[:error_rate_max])
        end

        def degraded_fallback_rate_max
          float_from_env(ENV_KEYS[:degraded_fallback_rate_max], DEFAULTS[:degraded_fallback_rate_max])
        end

        def retrieval_failure_rate_max
          float_from_env(ENV_KEYS[:retrieval_failure_rate_max], DEFAULTS[:retrieval_failure_rate_max])
        end

        def policy_blocked_rate_warn
          float_from_env(ENV_KEYS[:policy_blocked_rate_warn], DEFAULTS[:policy_blocked_rate_warn])
        end

        def citation_reask_rate_warn
          float_from_env(ENV_KEYS[:citation_reask_rate_warn], DEFAULTS[:citation_reask_rate_warn])
        end

        def orchestration_failure_rate_max
          float_from_env(ENV_KEYS[:orchestration_failure_rate_max], DEFAULTS[:orchestration_failure_rate_max])
        end

        private

        def integer_from_env(key, default)
          v = ENV[key].to_s.strip
          v.present? ? v.to_i : default
        end

        def float_from_env(key, default)
          v = ENV[key].to_s.strip
          v.present? ? v.to_f : default
        end
      end
    end
  end
end
