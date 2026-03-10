# frozen_string_literal: true

module Ai
  module Conversation
    # Deterministic memory budgeting: summary first, then recent messages (chronological).
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
        # Returns { memory_text:, memory_used:, summary_used:, recent_messages_count:, memory_truncated:, final_memory_chars: }
        def call(summary_text: nil, recent_messages: [], max_memory_chars: nil, max_recent_messages: nil)
          max_memory_chars ||= self.max_memory_chars
          max_recent_messages ||= self.max_recent_messages

          summary_text = summary_text.to_s.strip
          recent_messages = recent_messages.to_a.last(max_recent_messages) # cap count first

          if summary_text.blank? && recent_messages.empty?
            return {
              memory_text: '',
              memory_used: false,
              summary_used: false,
              recent_messages_count: 0,
              memory_truncated: false,
              final_memory_chars: 0
            }
          end

          formatted = recent_messages.map do |m|
            label = (m[:role].to_s == 'user') ? 'User' : 'Assistant'
            "#{label}: #{m[:content].to_s.strip}"
          end

          full_text = if summary_text.present?
            [summary_text, *formatted].join("\n\n")
          else
            formatted.join("\n\n")
          end

          memory_truncated = false
          final_message_count = formatted.size

          if full_text.length > max_memory_chars
            memory_truncated = true
            if summary_text.present?
              summary_part = summary_text
              remaining_budget = max_memory_chars - summary_part.length - 2
              if remaining_budget <= 0
                full_text = summary_part.truncate(max_memory_chars)
                final_message_count = 0
              else
                used = []
                used_chars = 0
                formatted.reverse_each do |blob|
                  need = used.empty? ? blob.length : blob.length + 2
                  break if used_chars + need > remaining_budget
                  used.unshift(blob)
                  used_chars += need
                end
                full_text = summary_part + "\n\n" + used.join("\n\n")
                final_message_count = used.size
              end
            else
              used = []
              used_chars = 0
              formatted.reverse_each do |blob|
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
            recent_messages_count: final_message_count,
            memory_truncated: memory_truncated,
            final_memory_chars: full_text.to_s.length
          }
        end
      end
    end
  end
end
