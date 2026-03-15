# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Async::SummaryRefreshEnqueuer do
  include ActiveJob::TestHelper
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }
  let(:session) { merchant.ai_chat_sessions.create! }

  before do
    allow(Ai::Observability::EventLogger).to receive(:log_ai_job)
  end

  describe '.enqueue_if_ok' do
    it 'enqueues RefreshConversationSummaryJob when session_id present' do
      expect {
        described_class.enqueue_if_ok(ai_chat_session_id: session.id, merchant_id: merchant.id)
      }.to have_enqueued_job(Ai::RefreshConversationSummaryJob).with(session.id)
    end

    it 'returns true when job was enqueued' do
      result = described_class.enqueue_if_ok(ai_chat_session_id: session.id)
      expect(result).to be true
    end

    it 'returns false when ai_chat_session_id blank' do
      result = described_class.enqueue_if_ok(ai_chat_session_id: nil)
      expect(result).to be false
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs).not_to include(a_hash_including('job_class' => 'Ai::RefreshConversationSummaryJob'))
    end

    it 'does not enqueue twice within TTL (duplicate suppression)' do
      expect { described_class.enqueue_if_ok(ai_chat_session_id: session.id) }.to have_enqueued_job(Ai::RefreshConversationSummaryJob)
      second = described_class.enqueue_if_ok(ai_chat_session_id: session.id)
      expect(second).to be false
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.select { |j| j['job_class'] == 'Ai::RefreshConversationSummaryJob' }.size).to eq(1)
    end

    it 'logs enqueued with session and merchant' do
      described_class.enqueue_if_ok(ai_chat_session_id: session.id, merchant_id: merchant.id, request_id: 'req-1')
      expect(Ai::Observability::EventLogger).to have_received(:log_ai_job).with(
        hash_including(phase: 'enqueued', job_class: 'Ai::RefreshConversationSummaryJob', ai_chat_session_id: session.id, merchant_id: merchant.id)
      )
    end
  end
end
