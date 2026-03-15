# frozen_string_literal: true

module Ai
  module Monitoring
    # Produces a structured health report from ai_request_audits: metrics per window,
    # SLO evaluation, and recent anomalies. Internal/dev use only.
    class HealthReporter
      WINDOWS = %w[15m 1h 24h].freeze

      def self.call(merchant_id: nil, time_windows: WINDOWS)
        new(merchant_id: merchant_id, time_windows: time_windows).call
      end

      def initialize(merchant_id: nil, time_windows: WINDOWS)
        @merchant_id = merchant_id
        @time_windows = time_windows
      end

      def call
        all_statuses = []
        metrics_by_window = {}

        @time_windows.each do |window|
          metrics = MetricsQuery.call(time_window: window, merchant_id: @merchant_id)
          metrics_by_window[window] = metrics
          statuses = SloEvaluator.call(metrics, time_window: window)
          all_statuses.concat(statuses)
        end

        overall = compute_overall_status(all_statuses)
        anomalies = AnomalyDetector.call(merchant_id: @merchant_id)

        HealthReport.new(
          overall_status: overall,
          metric_statuses: all_statuses,
          recent_anomalies: anomalies,
          evaluated_at: Time.current,
          time_windows: metrics_by_window
        )
      end

      private

      def compute_overall_status(statuses)
        has_unhealthy = statuses.any? { |s| s.status == 'unhealthy' }
        has_warning = statuses.any? { |s| s.status == 'warning' }
        return 'unhealthy' if has_unhealthy
        return 'warning' if has_warning
        'healthy'
      end
    end
  end
end
