# frozen_string_literal: true

module Ai
  # Builds conversation context from an AiChatSession for use with agents/GroqClient.
  # Output: summary_text (from session) + last N user/assistant messages in chronological order.
  class ConversationContextBuilder
    ALLOWED_ROLES = %w[user assistant].freeze

    def self.call(ai_chat_session, max_turns: 8)
      new(ai_chat_session, max_turns: max_turns).call
    end

    def initialize(ai_chat_session, max_turns: 8)
      @session = ai_chat_session
      @max_turns = max_turns
    end

    def call
      {
        summary_text: summary_text,
        recent_messages: recent_messages,
        memory_text: format_for_memory(exclude_last: true)
      }
    end

    # Returns array of { role:, content: } suitable for GroqClient (e.g. conversation_history).
    def to_groq_messages
      recent_messages.map { |m| { role: m[:role], content: m[:content].to_s } }
    end

    # Returns a single string suitable for Memory section (summary + recent messages formatted).
    def format_for_memory(exclude_last: false)
      parts = []
      parts << summary_text if summary_text.present?
      msgs = exclude_last && recent_messages.size > 1 ? recent_messages[0..-2] : recent_messages
      msgs.each do |m|
        label = m[:role] == 'user' ? 'User' : 'Assistant'
        parts << "#{label}: #{m[:content].to_s.strip}"
      end
      parts.join("\n\n")
    end

    private

    def summary_text
      return '' unless @session.respond_to?(:summary_text)

      @session.summary_text.to_s
    end

    def recent_messages
      return [] unless @session&.ai_chat_messages

      @session
        .ai_chat_messages
        .where(role: ALLOWED_ROLES)
        .order(created_at: :desc)
        .limit(@max_turns)
        .to_a
        .reverse
        .map { |m| { role: m.role, content: m.content } }
    end
  end
end
