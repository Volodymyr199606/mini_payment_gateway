# frozen_string_literal: true

module Ai
  module Monitoring
    # Queries ai_request_audits over configurable time windows and computes
    # health metrics: totals, percentiles, rates. Used by HealthReporter.
    class MetricsQuery
      WINDOWS = {
        '15m' => -> { 15.minutes.ago..Time.current },
        '1h' => -> { 1.hour.ago..Time.current },
        '24h' => -> { 24.hours.ago..Time.current }
      }.freeze

      def self.call(time_window: '1h', merchant_id: nil)
        new(time_window: time_window, merchant_id: merchant_id).call
      end

      def initialize(time_window: '1h', merchant_id: nil)
        @time_window = time_window.to_s
        @range = WINDOWS[@time_window]&.call || WINDOWS['1h'].call
        @merchant_id = merchant_id.presence
      end

      def call
        scope = AiRequestAudit.where(created_at: @range)
        scope = scope.where(merchant_id: @merchant_id) if @merchant_id.present?

        total = scope.count
        return empty_metrics(total) if total.zero?

        latency_values = scope.where.not(latency_ms: nil).pluck(:latency_ms)
        p50 = percentile(latency_values, 0.5)
        p95 = percentile(latency_values, 0.95)

        failed = scope.where(success: false).count
        fallback = scope.where(fallback_used: true).count
        tool_used = scope.where(tool_used: true).count
        tool_success = scope.where(tool_used: true, success: true).count
        citation_reask = scope.where(citation_reask_used: true).count
        orchestration_scope = scope.where("composition_mode = 'orchestration' OR agent_key = 'orchestration'")
        orchestration_total = orchestration_scope.count
        orchestration_failed = orchestration_scope.where(success: false).count

        # Retrieval "failure" proxy: fallback used on docs path (retriever_key present) or zero sections
        retrieval_failure_count = scope.where(fallback_used: true).where(
          "retriever_key IS NOT NULL OR COALESCE(retrieved_sections_count, 0) = 0"
        ).count

        policy_blocked = 0
        if AiRequestAudit.column_names.include?('authorization_denied')
          policy_blocked = scope.where('authorization_denied = true OR tool_blocked_by_policy = true').count
        end

        {
          time_window: @time_window,
          total_requests: total,
          p50_latency_ms: p50,
          p95_latency_ms: p95,
          error_rate: total.positive? ? (failed.to_f / total).round(4) : 0,
          error_count: failed,
          degraded_fallback_rate: total.positive? ? (fallback.to_f / total).round(4) : 0,
          degraded_fallback_count: fallback,
          tool_usage_rate: total.positive? ? (tool_used.to_f / total).round(4) : 0,
          tool_success_rate: tool_used.positive? ? (tool_success.to_f / tool_used).round(4) : 1.0,
          retrieval_failure_rate: total.positive? ? (retrieval_failure_count.to_f / total).round(4) : 0,
          retrieval_failure_count: retrieval_failure_count,
          orchestration_usage_rate: total.positive? ? (orchestration_total.to_f / total).round(4) : 0,
          orchestration_failure_rate: orchestration_total.positive? ? (orchestration_failed.to_f / orchestration_total).round(4) : 0,
          orchestration_failure_count: orchestration_failed,
          policy_blocked_rate: total.positive? ? (policy_blocked.to_f / total).round(4) : 0,
          policy_blocked_count: policy_blocked,
          citation_reask_rate: total.positive? ? (citation_reask.to_f / total).round(4) : 0,
          citation_reask_count: citation_reask,
          audit_write_failure_rate: 0, # Not tracked per-request in audits
          streaming_fallback_rate: total.positive? ? (fallback.to_f / total).round(4) : 0 # Proxy via fallback
        }
      end

      private

      def empty_metrics(total = 0)
        {
          time_window: @time_window,
          total_requests: total,
          p50_latency_ms: nil,
          p95_latency_ms: nil,
          error_rate: 0,
          error_count: 0,
          degraded_fallback_rate: 0,
          degraded_fallback_count: 0,
          tool_usage_rate: 0,
          tool_success_rate: 1.0,
          retrieval_failure_rate: 0,
          retrieval_failure_count: 0,
          orchestration_usage_rate: 0,
          orchestration_failure_rate: 0,
          orchestration_failure_count: 0,
          policy_blocked_rate: 0,
          policy_blocked_count: 0,
          citation_reask_rate: 0,
          citation_reask_count: 0,
          audit_write_failure_rate: 0,
          streaming_fallback_rate: 0
        }
      end

      def percentile(sorted_values, p)
        return nil if sorted_values.nil? || sorted_values.empty?
        arr = sorted_values.sort
        k = (p * (arr.size - 1) + 1).to_f
        f = k.floor
        c = k.ceil
        return arr[f - 1] if f == c
        (arr[f - 1] * (c - k) + arr[c - 1] * (k - f)).round
      end
    end
  end
end
