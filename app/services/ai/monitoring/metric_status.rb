# frozen_string_literal: true

module Ai
  module Monitoring
    # Single metric evaluation result: value, threshold, status, reason.
    MetricStatus = Struct.new(
      :metric_name,
      :value,
      :threshold,
      :status,
      :reason_code,
      :evaluated_at,
      :time_window,
      keyword_init: true
    ) do
      def self.healthy(metric_name:, value:, time_window:, threshold: nil)
        new(
          metric_name: metric_name,
          value: value,
          threshold: threshold,
          status: 'healthy',
          reason_code: nil,
          evaluated_at: Time.current,
          time_window: time_window
        )
      end

      def self.warning(metric_name:, value:, threshold:, reason_code:, time_window:)
        new(
          metric_name: metric_name,
          value: value,
          threshold: threshold,
          status: 'warning',
          reason_code: reason_code,
          evaluated_at: Time.current,
          time_window: time_window
        )
      end

      def self.unhealthy(metric_name:, value:, threshold:, reason_code:, time_window:)
        new(
          metric_name: metric_name,
          value: value,
          threshold: threshold,
          status: 'unhealthy',
          reason_code: reason_code,
          evaluated_at: Time.current,
          time_window: time_window
        )
      end

      def to_h
        {
          metric_name: metric_name,
          value: value,
          threshold: threshold,
          status: status,
          reason_code: reason_code,
          evaluated_at: evaluated_at&.iso8601,
          time_window: time_window
        }.compact
      end
    end
  end
end
