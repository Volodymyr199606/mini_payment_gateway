# frozen_string_literal: true

module Ai
  module Tools
    # Deterministic ledger summary via Reporting::LedgerSummary. Read-only.
    class GetLedgerSummary < BaseTool
      PRESETS = %w[all_time last_7_days last_week last_month today yesterday].freeze

      def call
        return error('merchant_id required') unless merchant_id.present?

        from_val, to_val = parse_range
        return error('Missing date range. Provide from/to or preset.') unless from_val && to_val

        summary = ::Reporting::LedgerSummary.new(
          merchant_id: merchant_id,
          from: from_val,
          to: to_val,
          currency: (@args['currency'] || 'USD').to_s.upcase,
          group_by: 'none'
        ).call

        ok(summary)
      rescue StandardError => e
        error(e.message, code: 'tool_error')
      end

      private

      def parse_range
        preset = @args['preset'].to_s.strip.downcase.presence
        if preset.present?
          return parse_preset(preset)
        end

        from_s = @args['from'].to_s.strip.presence
        to_s = @args['to'].to_s.strip.presence
        return [nil, nil] if from_s.blank? && to_s.blank?

        from_t = parse_time(from_s)
        to_t = parse_time(to_s)
        return [nil, nil] unless from_t && to_t

        [from_t, to_t]
      end

      def parse_preset(preset)
        zone = ActiveSupport::TimeZone['America/Los_Angeles']
        now = zone.now
        case preset
        when 'all_time'
          [Time.zone.parse('2000-01-01 00:00:00'), now]
        when 'last_7_days'
          [(now - 7.days).beginning_of_day, now]
        when 'last_week'
          [(now - 1.week).beginning_of_week, (now - 1.week).end_of_week]
        when 'last_month'
          [(now - 1.month).beginning_of_month, (now - 1.month).end_of_month]
        when 'today'
          [now.beginning_of_day, now]
        when 'yesterday'
          d = now - 1.day
          [d.beginning_of_day, d.end_of_day]
        else
          [nil, nil]
        end
      end

      def parse_time(str)
        return nil if str.blank?

        Time.zone.parse(str)
      rescue ArgumentError
        nil
      end
    end
  end
end
