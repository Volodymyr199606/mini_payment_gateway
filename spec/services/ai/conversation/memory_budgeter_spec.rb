# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Conversation::MemoryBudgeter do
  describe '.call' do
    it 'returns empty result when no summary and no messages' do
      result = described_class.call(summary_text: nil, recent_messages: [])
      expect(result[:memory_text]).to eq('')
      expect(result[:memory_used]).to be(false)
      expect(result[:summary_used]).to be(false)
      expect(result[:recent_messages_count]).to eq(0)
      expect(result[:memory_truncated]).to be(false)
      expect(result[:final_memory_chars]).to eq(0)
    end

    it 'includes summary first, then recent messages in chronological order' do
      result = described_class.call(
        summary_text: 'Summary here.',
        recent_messages: [
          { role: 'user', content: 'First' },
          { role: 'assistant', content: 'Second' }
        ],
        max_memory_chars: 2000,
        max_recent_messages: 8
      )
      expect(result[:memory_text]).to include('Summary here.')
      expect(result[:memory_text]).to include('User: First')
      expect(result[:memory_text]).to include('Assistant: Second')
      expect(result[:summary_used]).to be(true)
      expect(result[:recent_messages_count]).to eq(2)
    end

    it 'drops oldest recent messages first when memory budget is exceeded' do
      messages = 5.times.map { |i| { role: i.even? ? 'user' : 'assistant', content: "Message #{i} content here" } }
      result = described_class.call(
        summary_text: nil,
        recent_messages: messages,
        max_memory_chars: 50,
        max_recent_messages: 8
      )
      expect(result[:memory_truncated]).to be(true)
      expect(result[:final_memory_chars]).to be <= 50
      expect(result[:recent_messages_count]).to be < 5
      expect(result[:memory_text]).not_to include('Message 0') if result[:recent_messages_count] < 5
    end

    it 'caps recent messages by max_recent_messages' do
      messages = 20.times.map { |i| { role: 'user', content: "M#{i}" } }
      result = described_class.call(
        summary_text: nil,
        recent_messages: messages,
        max_memory_chars: 10_000,
        max_recent_messages: 5
      )
      expect(result[:recent_messages_count]).to eq(5)
    end

    it 'sets memory_truncated and final_memory_chars correctly' do
      result = described_class.call(
        summary_text: 'Short summary.',
        recent_messages: [{ role: 'user', content: 'Hi' }],
        max_memory_chars: 2000
      )
      expect(result[:memory_used]).to be(true)
      expect(result[:memory_truncated]).to be(false)
      expect(result[:final_memory_chars]).to eq(result[:memory_text].length)
      expect(result[:recent_messages_count]).to eq(1)
    end

    it 'includes current_topic, user_preferences, open_tasks when summary blank' do
      result = described_class.call(
        summary_text: nil,
        recent_messages: [{ role: 'user', content: 'Hi' }],
        current_topic: 'webhooks',
        user_preferences: 'Prefers email',
        open_tasks_or_followups: 'Verify webhook',
        max_memory_chars: 2000
      )
      expect(result[:memory_text]).to include('Current topic: webhooks')
      expect(result[:memory_text]).to include('User preferences: Prefers email')
      expect(result[:memory_text]).to include('Open tasks: Verify webhook')
      expect(result[:current_topic]).to eq('webhooks')
    end

    it 'returns metadata: summary_chars, current_topic, sanitization_applied' do
      result = described_class.call(
        summary_text: 'Summary here.',
        recent_messages: [{ role: 'user', content: 'Hi' }],
        current_topic: 'refunds',
        sanitization_applied: true
      )
      expect(result[:summary_chars]).to eq(13) # "Summary here."
      expect(result[:current_topic]).to eq('refunds')
      expect(result[:sanitization_applied]).to be(true)
    end
  end
end
