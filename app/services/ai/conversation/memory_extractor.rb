# frozen_string_literal: true

module Ai
  module Conversation
    # Extracts structured sections from persisted summary text.
    # Returns nil for sections that are absent or not clearly parseable.
    class MemoryExtractor
      # Use [\s\S] to match across newlines; (?=\n##|\z) = until next ## or end of string
      SECTION_TOPIC = /##\s*current\s+topic\s*\n([\s\S]*?)(?=\n##|\z)/i
      SECTION_FACTS = /##\s*facts\s*\n([\s\S]*?)(?=\n##|\z)/i
      SECTION_USER_PREFERENCES = /##\s*user\s*preferences\s*\n([\s\S]*?)(?=\n##|\z)/i
      SECTION_OPEN_TASKS = /##\s*open\s*tasks\s*\n([\s\S]*?)(?=\n##|\z)/i

      def self.call(summary_text)
        new(summary_text).call
      end

      def initialize(summary_text)
        @summary = summary_text.to_s.strip
      end

      def call
        return empty_result if @summary.blank?

        {
          current_topic: extract_section(SECTION_TOPIC),
          facts: extract_section(SECTION_FACTS),
          user_preferences: extract_section(SECTION_USER_PREFERENCES),
          open_tasks: extract_section(SECTION_OPEN_TASKS)
        }
      end

      private

      def empty_result
        { current_topic: nil, facts: nil, user_preferences: nil, open_tasks: nil }
      end

      def extract_section(pattern)
        m = @summary.match(pattern)
        return nil unless m

        text = m[1].to_s.strip
        text.presence
      end
    end
  end
end
