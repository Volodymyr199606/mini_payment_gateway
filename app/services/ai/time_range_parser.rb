# frozen_string_literal: true

module Ai
  # Parses natural time phrases into [from_time, to_time] in America/Los_Angeles.
  # Returns times at start/end of range for DB queries (created_at).
  # Rules: "last week" = previous Monday 00:00 to Sunday 23:59:59. Max range 365 days.
  class TimeRangeParser
    TIMEZONE = 'America/Los_Angeles'
    MAX_DAYS = 365

    PHRASES = {
      'today' => -> { [today_start, today_end] },
      'yesterday' => -> { [yesterday_start, yesterday_end] },
      'last 7 days' => -> { [days_ago_end(7), now] },
      'last week' => -> { [last_week_monday, last_week_sunday] },
      'this month' => -> { [this_month_start, now] },
      'last month' => -> { [last_month_start, last_month_end] }
    }.freeze

    class ParseError < StandardError; end

    def initialize(phrase)
      @phrase = phrase.to_s.strip.downcase
    end

    def call
      normalized = @phrase.gsub(/\s+/, ' ')
      handler = PHRASES[normalized]
      raise ParseError, "Unsupported time range: #{@phrase.inspect}" unless handler

      from_time, to_time = handler.call
      range_days = ((to_time - from_time) / 1.day).ceil
      raise ParseError, "Time range exceeds maximum of #{MAX_DAYS} days" if range_days > MAX_DAYS

      [from_time, to_time]
    end

    class << self
      def parse(phrase)
        new(phrase).call
      end

      def zone
        @zone ||= ActiveSupport::TimeZone[TIMEZONE]
      end

      def now
        zone.now
      end

      def today_start
        now.beginning_of_day
      end

      def today_end
        now.end_of_day
      end

      def yesterday_start
        (now - 1.day).beginning_of_day
      end

      def yesterday_end
        (now - 1.day).end_of_day
      end

      def days_ago_end(days)
        (now - days.days).beginning_of_day
      end

      def last_week_monday
        (now - 1.week).beginning_of_week
      end

      def last_week_sunday
        (now - 1.week).end_of_week
      end

      def this_month_start
        now.beginning_of_month
      end

      def last_month_start
        (now - 1.month).beginning_of_month
      end

      def last_month_end
        (now - 1.month).end_of_month
      end
    end
  end
end
