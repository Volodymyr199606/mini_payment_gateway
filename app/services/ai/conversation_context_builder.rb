# frozen_string_literal: true

module Ai
  # Builds conversation context from an AiChatSession for use with agents/GroqClient.
  # Returns structured memory: summary_text, recent_messages, user_preferences, open_tasks, current_topic.
  # Does not invent data; returns nil/empty for unavailable sections.
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
      summary = summary_text
      extracted = extracted_memory(summary)
      recent = recent_messages

      {
        summary_text: summary,
        recent_messages: recent,
        user_preferences: extracted[:user_preferences],
        open_tasks_or_followups: extracted[:open_tasks],
        current_topic: resolve_current_topic(summary, recent, extracted)
      }
    end

    def to_groq_messages
      recent_messages.map { |m| { role: m[:role], content: m[:content].to_s } }
    end

    private

    def summary_text
      return '' unless @session.respond_to?(:summary_text)

      @session.summary_text.to_s
    end

    def extracted_memory(summary)
      return { user_preferences: nil, open_tasks: nil, current_topic: nil, facts: nil } if summary.blank?

      Ai::Conversation::MemoryExtractor.call(summary)
    end

    def resolve_current_topic(summary, recent, extracted)
      extracted[:current_topic].presence ||
        stored_session_topic ||
        Ai::Conversation::CurrentTopicDetector.call(recent)
    end

    def stored_session_topic
      @session.respond_to?(:current_topic) ? @session.current_topic.to_s.strip.presence : nil
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
        .map { |m| h = { role: m.role, content: m.content }; h[:agent] = m.agent if m.respond_to?(:agent); h }
    end
  end
end
