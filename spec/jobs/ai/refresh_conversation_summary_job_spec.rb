# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::RefreshConversationSummaryJob, type: :job do
  include ActiveJob::TestHelper
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }
  let(:session) { merchant.ai_chat_sessions.create! }

  before do
    allow(Ai::Observability::EventLogger).to receive(:log_ai_job)
  end

  describe '#perform' do
    it 'calls ConversationSummarizer with the session' do
      summarizer_result = { summary: 'Summary.', updated: false }
      allow(Ai::ConversationSummarizer).to receive(:call).with(session).and_return(summarizer_result)

      perform_enqueued_jobs do
        described_class.perform_later(session.id)
      end

      expect(Ai::ConversationSummarizer).to have_received(:call).with(session)
    end

    it 'does not raise when session is missing' do
      perform_enqueued_jobs do
        described_class.perform_later(999_999)
      end
      expect(Ai::Observability::EventLogger).to have_received(:log_ai_job).with(hash_including(phase: 'performed', skipped: 'session_not_found'))
    end

    it 'logs performed with duration and summary_updated' do
      allow(Ai::ConversationSummarizer).to receive(:call).and_return({ summary: 'S', updated: true })

      perform_enqueued_jobs do
        described_class.perform_later(session.id)
      end

      expect(Ai::Observability::EventLogger).to have_received(:log_ai_job).with(
        hash_including(phase: 'performed', job_class: 'Ai::RefreshConversationSummaryJob', summary_updated: true)
      )
    end

    it 'logs failed and re-raises on summarizer error' do
      allow(Ai::ConversationSummarizer).to receive(:call).and_raise(StandardError.new('Groq down'))

      described_class.perform_later(session.id)

      # Rails' `perform_enqueued_jobs { ... }` block form uses
      # ActiveSupport's `assert_nothing_raised`, which wraps raised exceptions
      # as `Minitest::UnexpectedError`. Using the non-block form lets the
      # original exception class/message propagate.
      expect { perform_enqueued_jobs }.to raise_error(StandardError, 'Groq down')

      expect(Ai::Observability::EventLogger).to have_received(:log_ai_job).with(
        hash_including(phase: 'failed', error_class: 'StandardError', error_message: 'Groq down')
      )
    end
  end
end
