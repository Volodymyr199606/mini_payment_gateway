# frozen_string_literal: true

module Ai
  # Summarizes an AiChatSession conversation via Groq and persists summary_text / summary_updated_at.
  # Only runs when message count since last summary exceeds threshold, or summary is blank with enough messages.
  # Sanitizes messages before sending to avoid storing secrets.
  class ConversationSummarizer
    NEW_MESSAGES_THRESHOLD = 8
    MIN_MESSAGES_FOR_FIRST_SUMMARY = 6
    SUMMARIZE_PROMPT = <<~TEXT
      Summarize the conversation so far in 5-10 bullet points. Preserve user preferences and important facts. Omit secrets and credentials. Output only the bullet list, no preamble.
    TEXT

    def self.call(ai_chat_session)
      new(ai_chat_session).call
    end

    def initialize(ai_chat_session)
      @session = ai_chat_session
    end

    def call
      return current_summary unless should_summarize?

      sanitized_messages = build_sanitized_messages
      return current_summary if sanitized_messages.empty?

      summary = fetch_summary_from_groq(sanitized_messages)
      return current_summary if summary.blank?

      persist_summary(summary)
      summary
    end

    private

    def current_summary
      @session.respond_to?(:summary_text) ? @session.summary_text.to_s : ''
    end

    def should_summarize?
      messages = messages_for_summary_decision
      count_since = count_messages_since_summary(messages)

      if current_summary.blank?
        return messages.size >= MIN_MESSAGES_FOR_FIRST_SUMMARY
      end

      count_since >= NEW_MESSAGES_THRESHOLD
    end

    def messages_for_summary_decision
      return [] unless @session&.ai_chat_messages

      @session.ai_chat_messages.where(role: %w[user assistant]).order(created_at: :asc).to_a
    end

    def count_messages_since_summary(messages)
      return messages.size if @session.summary_updated_at.blank?

      cutoff = @session.summary_updated_at
      messages.count { |m| m.created_at > cutoff }
    end

    def build_sanitized_messages
      messages_for_summary_decision.map do |m|
        { role: m.role, content: MessageSanitizer.sanitize(m.content) }
      end
    end

    def fetch_summary_from_groq(sanitized_messages)
      conversation = sanitized_messages.map { |m| { role: m[:role], content: m[:content].to_s } }
      messages = [
        { role: 'system', content: SUMMARIZE_PROMPT },
        *conversation,
        { role: 'user', content: 'Provide the summary now.' }
      ]
      result = groq_client.chat(messages: messages, temperature: 0.2, max_tokens: 512)
      content = result[:content].to_s.strip
      # Never persist if response looks like it might contain secrets (basic guard)
      return '' if content.include?(MessageSanitizer::REDACT_PLACEHOLDER)

      content
    end

    def persist_summary(summary)
      # Never store raw secrets: sanitize again in case model echoed something
      safe = MessageSanitizer.sanitize(summary)
      @session.update!(summary_text: safe, summary_updated_at: Time.current)
    end

    def groq_client
      @groq_client ||= GroqClient.new
    end
  end
end
