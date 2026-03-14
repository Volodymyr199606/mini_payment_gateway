# frozen_string_literal: true

module Ai
  module Analytics
    # Queries ai_request_audits for analytics. Supports time range and optional merchant filter.
    # Safe for internal/dev use only.
    class DashboardQuery
      PRESETS = {
        'today' => -> { Time.current.beginning_of_day..Time.current.end_of_day },
        '7d' => -> { 7.days.ago..Time.current },
        '30d' => -> { 30.days.ago..Time.current }
      }.freeze

      def self.call(scope: nil, time_preset: '7d', merchant_id: nil)
        new(scope: scope, time_preset: time_preset, merchant_id: merchant_id).call
      end

      def initialize(scope: nil, time_preset: '7d', merchant_id: nil)
        @base = scope || AiRequestAudit
        @time_range = PRESETS[time_preset.to_s].presence&.call || PRESETS['7d'].call
        @merchant_id = merchant_id.presence
      end

      def call
        rel = @base.where(created_at: @time_range)
        rel = rel.where(merchant_id: @merchant_id) if @merchant_id.present?
        rel
      end

      def time_range
        @time_range
      end
    end
  end
end
