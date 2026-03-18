# frozen_string_literal: true

module Ai
  # Offloads conversation summarization so the request path stays fast.
  # Calls ConversationSummarizer (Groq) only when session meets threshold/topic-change.
  class RefreshConversationSummaryJob < Ai::BaseJob
    # Ensure the job is enqueued after the DB transaction commits, so it can
    # safely read the final AiChatSession state.
    self.enqueue_after_transaction_commit = true

    # ActiveJob retries wrap exceptions in test adapters, which breaks specs that
    # assert the original exception class/message. Disable retries in test.
    retry_on StandardError, wait: :polynomially_longer, attempts: 2 unless Rails.env.test?
    discard_on ActiveJob::DeserializationError

    def perform(ai_chat_session_id)
      session = AiChatSession.find_by(id: ai_chat_session_id)
      unless session
        self.class.log_performed(job_class: self.class.name, ai_chat_session_id: ai_chat_session_id, skipped: 'session_not_found')
        return
      end

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = ::Ai::ConversationSummarizer.call(session)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

      self.class.log_performed(
        job_class: self.class.name,
        ai_chat_session_id: ai_chat_session_id,
        merchant_id: session.merchant_id,
        duration_ms: duration_ms,
        summary_updated: result[:updated]
      )
    rescue StandardError => e
      self.class.log_failed(
        job_class: self.class.name,
        ai_chat_session_id: ai_chat_session_id,
        error_class: e.class.name,
        error_message: e.message
      )
      raise
    end
  end
end
