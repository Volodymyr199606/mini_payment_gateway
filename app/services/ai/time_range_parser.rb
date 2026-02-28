# frozen_string_literal: true

module Ai
  # Parses natural time phrases into [from_time, to_time] in America/Los_Angeles.
  # Returns times at start/end of range for DB queries (created_at).
  # Rules: "last week" = previous Monday 00:00 to Sunday 23:59:59.
  # Max range 365 days applies ONLY when a range is explicitly requested, not for all-time default.
  class TimeRangeParser
    TIMEZONE = 'America/Los_Angeles'
    MAX_DAYS = 365
    ALL_TIME_START = ActiveSupport::TimeZone[TIMEZONE].parse('2000-01-01 00:00:00')

    PHRASES = {
      'today' => -> { [today_start, today_end] },
      'yesterday' => -> { [yesterday_start, yesterday_end] },
      'last 7 days' => -> { [days_ago_end(7), now] },
      'last week' => -> { [last_week_monday, last_week_sunday] },
      'this month' => -> { [this_month_start, now] },
      'last month' => -> { [last_month_start, last_month_end] },
      'all time' => -> { [ALL_TIME_START, now] },
      'all-time' => -> { [ALL_TIME_START, now] }
    }.freeze

    # Order for extraction: longest first so "last 7 days" matches before "last week"
    PHRASE_KEYS_ORDERED = PHRASES.keys.sort_by { |k| -k.length }.freeze

    class ParseError < StandardError; end

    def initialize(phrase)
      @phrase = phrase.to_s.strip.downcase.gsub(/\s+/, ' ')
    end

    def call
      handler = PHRASES[@phrase]
      raise ParseError, "Unsupported time range: #{@phrase.inspect}" unless handler

      from_time, to_time = handler.call
      # 365-day cap only for explicit ranges (not all-time)
      unless all_time_range?(from_time, to_time)
        range_days = ((to_time - from_time) / 1.day).ceil
        raise ParseError, "Time range exceeds maximum of #{MAX_DAYS} days" if range_days > MAX_DAYS
      end

      [from_time, to_time]
    end

    def all_time_range?(from_time, _to_time)
      from_time <= ALL_TIME_START
    end

    # Extracts a time phrase from the message and parses it.
    # Returns a hash: { from:, to:, inferred:, default_used:, range_label: }
    # When no phrase is found, defaults to all-time with inferred: true, default_used: "all_time".
    def self.extract_and_parse(message)
      msg = message.to_s.downcase.strip
      phrase = PHRASE_KEYS_ORDERED.find { |p| msg.include?(p) }

      if phrase
        from_time, to_time = parse(phrase)
        range_label = phrase
        { from: from_time, to: to_time, inferred: false, default_used: nil, range_label: range_label }
      else
        from_time = ALL_TIME_START
        to_time = zone.now
        range_label = "#{from_time.strftime('%Y-%m-%d')} to #{to_time.strftime('%Y-%m-%d')} (all-time)"
        { from: from_time, to: to_time, inferred: true, default_used: 'all_time', range_label: range_label }
      end
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
