# frozen_string_literal: true

module Ai
  # Precomputes AI request audit aggregates and stores in cache for analytics dashboard.
  # Run periodically (e.g. hourly) or on-demand; does not run per request.
  class RollupRequestAuditMetricsJob < Ai::BaseJob
    queue_as :default
    CACHE_KEY_PREFIX = 'ai:rollup'
    CACHE_TTL = 1.hour

    def perform(period: '7d')
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      scope = ::Ai::Analytics::DashboardQuery.call(time_preset: period)
      metrics = ::Ai::Analytics::MetricsBuilder.call(scope)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

      cache_key = "#{CACHE_KEY_PREFIX}:#{period}:#{Time.current.to_date}"
      Rails.cache.write(cache_key, metrics[:summary].to_h, expires_in: CACHE_TTL)

      self.class.log_performed(
        job_class: self.class.name,
        duration_ms: duration_ms,
        period: period,
        total_requests: metrics.dig(:summary, :total_requests)
      )
    rescue StandardError => e
      self.class.log_failed(
        job_class: self.class.name,
        error_class: e.class.name,
        error_message: e.message,
        period: period
      )
      raise
    end
  end
end
