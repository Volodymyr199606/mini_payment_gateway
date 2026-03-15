# frozen_string_literal: true

module Ai
  module Monitoring
    # Result of health check: overall status, metric statuses, anomalies.
    HealthReport = Struct.new(
      :overall_status,
      :metric_statuses,
      :recent_anomalies,
      :evaluated_at,
      :time_windows,
      keyword_init: true
    ) do
      def to_h
        {
          overall_status: overall_status,
          metric_statuses: metric_statuses&.map(&:to_h),
          recent_anomalies: recent_anomalies,
          evaluated_at: evaluated_at&.iso8601,
          time_windows: time_windows
        }
      end

      def healthy?
        overall_status == 'healthy'
      end

      def warning?
        overall_status == 'warning'
      end

      def unhealthy?
        overall_status == 'unhealthy'
      end
    end
  end
end
