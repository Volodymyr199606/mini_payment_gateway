# frozen_string_literal: true

module Ai
  module Monitoring
    # Evaluates metrics against SLO thresholds and returns MetricStatus for each.
    class SloEvaluator
      def self.call(metrics, time_window:)
        new(metrics: metrics, time_window: time_window).call
      end

      def initialize(metrics:, time_window:)
        @metrics = metrics
        @time_window = time_window.to_s
      end

      def call
        statuses = []
        cfg = SloConfig

        # p95 latency
        p95 = @metrics[:p95_latency_ms]
        thresh_p95 = cfg.p95_latency_ms
        if p95.nil?
          statuses << MetricStatus.healthy(metric_name: 'p95_latency_ms', value: nil, time_window: @time_window, threshold: thresh_p95)
        elsif p95 > thresh_p95
          statuses << MetricStatus.unhealthy(
            metric_name: 'p95_latency_ms',
            value: p95,
            threshold: thresh_p95,
            reason_code: 'p95_above_threshold',
            time_window: @time_window
          )
        else
          statuses << MetricStatus.healthy(metric_name: 'p95_latency_ms', value: p95, time_window: @time_window, threshold: thresh_p95)
        end

        # error rate
        err_rate = @metrics[:error_rate].to_f
        if err_rate > cfg.error_rate_max
          statuses << MetricStatus.unhealthy(
            metric_name: 'error_rate',
            value: err_rate,
            threshold: cfg.error_rate_max,
            reason_code: 'error_rate_above_threshold',
            time_window: @time_window
          )
        else
          statuses << MetricStatus.healthy(metric_name: 'error_rate', value: err_rate, time_window: @time_window, threshold: cfg.error_rate_max)
        end

        # degraded fallback rate
        fallback_rate = @metrics[:degraded_fallback_rate].to_f
        if fallback_rate > cfg.degraded_fallback_rate_max
          statuses << MetricStatus.warning(
            metric_name: 'degraded_fallback_rate',
            value: fallback_rate,
            threshold: cfg.degraded_fallback_rate_max,
            reason_code: 'fallback_rate_above_threshold',
            time_window: @time_window
          )
        else
          statuses << MetricStatus.healthy(metric_name: 'degraded_fallback_rate', value: fallback_rate, time_window: @time_window, threshold: cfg.degraded_fallback_rate_max)
        end

        # retrieval failure rate
        retrieval_rate = @metrics[:retrieval_failure_rate].to_f
        if retrieval_rate > cfg.retrieval_failure_rate_max
          statuses << MetricStatus.warning(
            metric_name: 'retrieval_failure_rate',
            value: retrieval_rate,
            threshold: cfg.retrieval_failure_rate_max,
            reason_code: 'retrieval_failure_above_threshold',
            time_window: @time_window
          )
        else
          statuses << MetricStatus.healthy(metric_name: 'retrieval_failure_rate', value: retrieval_rate, time_window: @time_window, threshold: cfg.retrieval_failure_rate_max)
        end

        # policy blocked (informational/warning)
        policy_rate = @metrics[:policy_blocked_rate].to_f
        if policy_rate > cfg.policy_blocked_rate_warn
          statuses << MetricStatus.warning(
            metric_name: 'policy_blocked_rate',
            value: policy_rate,
            threshold: cfg.policy_blocked_rate_warn,
            reason_code: 'policy_blocked_spike',
            time_window: @time_window
          )
        else
          statuses << MetricStatus.healthy(metric_name: 'policy_blocked_rate', value: policy_rate, time_window: @time_window, threshold: cfg.policy_blocked_rate_warn)
        end

        # citation reask
        reask_rate = @metrics[:citation_reask_rate].to_f
        if reask_rate > cfg.citation_reask_rate_warn
          statuses << MetricStatus.warning(
            metric_name: 'citation_reask_rate',
            value: reask_rate,
            threshold: cfg.citation_reask_rate_warn,
            reason_code: 'citation_reask_above_threshold',
            time_window: @time_window
          )
        else
          statuses << MetricStatus.healthy(metric_name: 'citation_reask_rate', value: reask_rate, time_window: @time_window, threshold: cfg.citation_reask_rate_warn)
        end

        # orchestration failure (only meaningful when orchestration is used)
        orch_fail = @metrics[:orchestration_failure_rate].to_f
        if @metrics[:orchestration_usage_rate].to_f > 0 && orch_fail > cfg.orchestration_failure_rate_max
          statuses << MetricStatus.warning(
            metric_name: 'orchestration_failure_rate',
            value: orch_fail,
            threshold: cfg.orchestration_failure_rate_max,
            reason_code: 'orchestration_failure_above_threshold',
            time_window: @time_window
          )
        else
          statuses << MetricStatus.healthy(metric_name: 'orchestration_failure_rate', value: orch_fail, time_window: @time_window, threshold: cfg.orchestration_failure_rate_max)
        end

        statuses
      end
    end
  end
end
