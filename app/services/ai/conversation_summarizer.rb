# frozen_string_literal: true

module Ai
  # Summarizes an AiChatSession conversation via Groq and persists summary_text / summary_updated_at.
  # Uses trigger rules to avoid summarizing on every request. Structured format with sanitization.
  class ConversationSummarizer
    NEW_MESSAGES_THRESHOLD = 10
    MIN_MESSAGES_FOR_FIRST_SUMMARY = 10
    MIN_SUMMARY_CHARS = 800
    MAX_SUMMARY_LENGTH = 1200

    SECTION_CURRENT_TOPIC = '## Current topic'
    SECTION_FACTS = '## Facts'
    SECTION_USER_PREFERENCES = '## User preferences'
    SECTION_OPEN_TASKS = '## Open tasks'

    SUMMARIZE_PROMPT = <<~TEXT
      Summarize the conversation in exactly four sections. Use these headings on their own lines (no extra punctuation):
      #{SECTION_CURRENT_TOPIC}
      #{SECTION_FACTS}
      #{SECTION_USER_PREFERENCES}
      #{SECTION_OPEN_TASKS}

      Under each heading write 2-5 short bullet points. Do NOT include secrets, API keys, credentials, or tokens. Skip sections with nothing relevant (e.g. "None" for open tasks). Do not summarize irrelevant small talk unless it affects future responses. Keep the entire reply between #{MIN_SUMMARY_CHARS} and #{MAX_SUMMARY_LENGTH} characters. Output only the four sections, no preamble.
    TEXT

    def self.call(ai_chat_session)
      new(ai_chat_session).call
    end

    def initialize(ai_chat_session)
      @session = ai_chat_session
    end

    def call
      unless should_summarize?
        return { summary: current_summary, updated: false }
      end

      sanitized_messages = build_sanitized_messages
      return { summary: current_summary, updated: false } if sanitized_messages.empty?

      summary = fetch_summary_from_groq(sanitized_messages)
      return { summary: current_summary, updated: false } if summary.blank?

      capped = cap_summary_length(summary)
      detected_topic = detect_topic_from_recent
      persist_summary(capped, detected_topic)
      { summary: capped, updated: true }
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

      return true if count_since >= NEW_MESSAGES_THRESHOLD
      return true if topic_changed?(messages)

      false
    end

    def topic_changed?(messages)
      return false unless @session.respond_to?(:current_topic)
      return false if messages.size < 4

      recent = messages.last(6).map { |m| { role: m.role, content: m.content } }
      detected = ::Ai::Conversation::CurrentTopicDetector.call(recent)
      stored = @session.current_topic.to_s.strip

      return false if detected.blank?
      return false if stored.blank?
      # Different topic when detected differs from stored (normalize for comparison)
      detected.to_s.downcase.tr(' ', '_') != stored.to_s.downcase.tr(' ', '_')
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
        { role: m.role, content: sanitize_for_summary(m.content) }
      end
    end

    def sanitize_for_summary(text)
      MessageSanitizer.sanitize(text)
    end

    def detect_topic_from_recent
      messages = messages_for_summary_decision.last(8).map { |m| { role: m.role, content: m.content } }
      ::Ai::Conversation::CurrentTopicDetector.call(messages)
    end

    def fetch_summary_from_groq(sanitized_messages)
      conversation = sanitized_messages.map { |m| { role: m[:role], content: m[:content].to_s } }
      messages = [
        { role: 'system', content: SUMMARIZE_PROMPT },
        *conversation,
        { role: 'user', content: 'Provide the summary now.' }
      ]
      result = groq_client.chat(messages: messages, temperature: 0.2, max_tokens: 450)
      content = result[:content].to_s.strip
      return '' if content.include?(MessageSanitizer::REDACT_PLACEHOLDER)

      content
    end

    def cap_summary_length(summary)
      return summary if summary.length <= MAX_SUMMARY_LENGTH

      summary.truncate(MAX_SUMMARY_LENGTH)
    end

    def persist_summary(summary, detected_topic = nil)
      safe = MessageSanitizer.sanitize(summary)
      attrs = { summary_text: safe, summary_updated_at: Time.current }
      attrs[:current_topic] = detected_topic if @session.respond_to?(:current_topic=) && detected_topic.present?
      @session.update!(attrs)
    end

    def groq_client
      @groq_client ||= GroqClient.new
    end
  end
end
