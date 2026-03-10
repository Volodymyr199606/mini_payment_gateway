# frozen_string_literal: true

module Ai
  module Conversation
    # Deterministic memory budgeting: summary, current_topic, user_preferences, open_tasks, recent messages.
    # When over budget, drops oldest messages first. Respects AI_MAX_MEMORY_CHARS and AI_MAX_RECENT_MESSAGES.
    class MemoryBudgeter
      DEFAULT_MAX_MEMORY_CHARS = 2000
      DEFAULT_MAX_RECENT_MESSAGES = 8

      class << self
        def max_memory_chars
          (ENV['AI_MAX_MEMORY_CHARS'].presence || DEFAULT_MAX_MEMORY_CHARS).to_i
        end

        def max_recent_messages
          (ENV['AI_MAX_RECENT_MESSAGES'].presence || DEFAULT_MAX_RECENT_MESSAGES).to_i
        end

        # summary_text: string (optional)
        # recent_messages: array of { role:, content: } in chronological order (oldest first)
        # user_preferences: string or nil (optional)
        # open_tasks_or_followups: string or nil (optional)
        # current_topic: string or nil (optional)
        # sanitization_applied: boolean (optional, for metadata)
        # Returns { memory_text:, memory_used:, summary_used:, summary_updated:, summary_chars:, recent_messages_count:, current_topic:, memory_truncated:, final_memory_chars:, sanitization_applied: }
        def call(
          summary_text: nil,
          recent_messages: [],
          user_preferences: nil,
          open_tasks_or_followups: nil,
          current_topic: nil,
          sanitization_applied: false,
          max_memory_chars: nil,
          max_recent_messages: nil
        )
          max_memory_chars ||= self.max_memory_chars
          max_recent_messages ||= self.max_recent_messages

          summary_text = summary_text.to_s.strip
          recent_messages = recent_messages.to_a.last(max_recent_messages)
          user_preferences = user_preferences.to_s.strip.presence
          open_tasks = open_tasks_or_followups.to_s.strip.presence
          current_topic = current_topic.to_s.strip.presence

          if summary_text.blank? && recent_messages.empty? && user_preferences.blank? && open_tasks.blank? && current_topic.blank?
            return empty_result(0)
          end

          # When summary exists it already includes Current topic, Facts, User preferences, Open tasks.
          # Only add standalone current_topic/user_preferences/open_tasks when summary is blank.
          parts = []
          if summary_text.present?
            parts << summary_text
          else
            parts << "Current topic: #{current_topic}" if current_topic.present?
            parts << "User preferences: #{user_preferences}" if user_preferences.present?
            parts << "Open tasks: #{open_tasks}" if open_tasks.present?
          end

          formatted_msgs = recent_messages.map do |m|
            label = (m[:role].to_s == 'user') ? 'User' : 'Assistant'
            "#{label}: #{m[:content].to_s.strip}"
          end

          header = parts.join("\n\n")
          full_text = if header.present?
            [header, *formatted_msgs].join("\n\n")
          else
            formatted_msgs.join("\n\n")
          end

          memory_truncated = false
          final_message_count = formatted_msgs.size

          if full_text.length > max_memory_chars
            memory_truncated = true
            if header.present?
              remaining_budget = max_memory_chars - header.length - 2
              if remaining_budget <= 0
                full_text = header.truncate(max_memory_chars)
                final_message_count = 0
              else
                used = []
                used_chars = 0
                formatted_msgs.reverse_each do |blob|
                  need = used.empty? ? blob.length : blob.length + 2
                  break if used_chars + need > remaining_budget

                  used.unshift(blob)
                  used_chars += need
                end
                full_text = header + "\n\n" + used.join("\n\n")
                final_message_count = used.size
              end
            else
              used = []
              used_chars = 0
              formatted_msgs.reverse_each do |blob|
                need = used.empty? ? blob.length : blob.length + 2
                break if used_chars + need > max_memory_chars

                used.unshift(blob)
                used_chars += need
              end
              full_text = used.join("\n\n")
              final_message_count = used.size
            end
          end

          {
            memory_text: full_text.to_s,
            memory_used: full_text.present?,
            summary_used: summary_text.present?,
            summary_updated: false, # Caller sets from summarizer result when known
            summary_chars: summary_text.length,
            recent_messages_count: final_message_count,
            current_topic: current_topic,
            memory_truncated: memory_truncated,
            final_memory_chars: full_text.to_s.length,
            sanitization_applied: sanitization_applied
          }
        end

        private

        def empty_result(summary_chars = 0)
          {
            memory_text: '',
            memory_used: false,
            summary_used: false,
            summary_updated: false,
            summary_chars: summary_chars,
            recent_messages_count: 0,
            current_topic: nil,
            memory_truncated: false,
            final_memory_chars: 0,
            sanitization_applied: false
          }
        end
      end
    end
  end
end
