# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::ConversationSummarizer do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }
  let(:session) { merchant.ai_chat_sessions.create! }

  def add_message(role, content, created_at: nil)
    msg = session.ai_chat_messages.create!(role: role, content: content, merchant_id: merchant.id)
    msg.update_column(:created_at, created_at) if created_at
    msg
  end

  describe 'threshold: when summarization runs' do
    it 'does not summarize when summary is blank and message count < 10' do
      2.times { |i| add_message('user', "Q#{i}"); add_message('assistant', "A#{i}") } # 4 messages
      expect(Ai::GroqClient).not_to receive(:new)

      result = described_class.call(session)
      expect(result).to eq('')
      expect(session.reload.summary_text).to be_blank
    end

    it 'summarizes when summary is blank and message count >= 10' do
      10.times { |i| add_message('user', "Q#{i}"); add_message('assistant', "A#{i}") }
      client = instance_double(Ai::GroqClient, chat: { content: '- User asked about refunds.', model_used: 'test', fallback_used: false })
      allow(Ai::GroqClient).to receive(:new).and_return(client)

      result = described_class.call(session)
      expect(result).to include('User asked about refunds')
      expect(session.reload.summary_text).to be_present
      expect(session.summary_updated_at).to be_present
    end

    it 'does not summarize when messages since summary_updated_at are below threshold (10)' do
      past = 2.hours.ago
      4.times do |i|
        add_message('user', "Q#{i}", created_at: past + i.minutes)
        add_message('assistant', "A#{i}", created_at: past + i.minutes + 30.seconds)
      end
      session.update!(summary_text: 'Prior summary.', summary_updated_at: 1.hour.ago)

      expect(Ai::GroqClient).not_to receive(:new)
      result = described_class.call(session)
      expect(result).to eq('Prior summary.')
      expect(session.reload.summary_text).to eq('Prior summary.')
    end

    it 'summarizes when messages since summary_updated_at >= 10' do
      cutoff = 1.hour.ago
      session.update!(summary_text: 'Old summary.', summary_updated_at: cutoff)
      # Add 10 messages with created_at after cutoff so they count as "new since summary"
      10.times do |i|
        add_message('user', "Q#{i}", created_at: cutoff + (i + 1).minutes)
        add_message('assistant', "A#{i}", created_at: cutoff + (i + 1).minutes + 30.seconds)
      end
      session.reload
      client = instance_double(Ai::GroqClient, chat: { content: '- Refunds and capture discussed.', model_used: 'test', fallback_used: false })
      allow(Ai::GroqClient).to receive(:new).and_return(client)

      result = described_class.call(session)
      expect(result).to be_present
      session.reload
      expect(session.summary_text).to include('Refunds and capture')
      expect(session.summary_updated_at).to be >= cutoff
    end
  end

  describe 'summary cap and format' do
    it 'caps persisted summary at MAX_SUMMARY_LENGTH (1200 chars)' do
      long_content = "## Facts\n- A\n\n## User preferences\n- B\n\n## Open tasks\n- C\n" + ('x' * 2000)
      10.times { |i| add_message('user', "Q#{i}"); add_message('assistant', "A#{i}") }
      client = instance_double(Ai::GroqClient, chat: { content: long_content, model_used: 'test', fallback_used: false })
      allow(Ai::GroqClient).to receive(:new).and_return(client)

      described_class.call(session)
      expect(session.reload.summary_text.length).to be <= described_class::MAX_SUMMARY_LENGTH
    end

    it 'persisted summary includes the three section headings when model returns them' do
      content = <<~TEXT
        ## Facts
        - User asked about refunds.
        ## User preferences
        - Prefers email.
        ## Open tasks
        - None.
      TEXT
      10.times { |i| add_message('user', "Q#{i}"); add_message('assistant', "A#{i}") }
      client = instance_double(Ai::GroqClient, chat: { content: content.strip, model_used: 'test', fallback_used: false })
      allow(Ai::GroqClient).to receive(:new).and_return(client)

      described_class.call(session)
      summary = session.reload.summary_text
      expect(summary).to include(described_class::SECTION_FACTS)
      expect(summary).to include(described_class::SECTION_USER_PREFERENCES)
      expect(summary).to include(described_class::SECTION_OPEN_TASKS)
    end
  end

  describe 'sanitizer integration' do
    it 'does not send raw secrets to Groq' do
      add_message('user', 'My api_key=sk_live_abc123def456')
      add_message('assistant', 'OK')
      9.times { |i| add_message('user', "Q#{i}"); add_message('assistant', "A#{i}") } # 20 total so >= 10

      sent_messages = []
      client = instance_double(Ai::GroqClient)
      allow(client).to receive(:chat) do |messages:, temperature: nil, max_tokens: nil|
        sent_messages.replace(messages)
        { content: '- User shared preferences.', model_used: 'test', fallback_used: false }
      end
      allow(Ai::GroqClient).to receive(:new).and_return(client)

      described_class.call(session)
      flat = sent_messages.map { |m| m[:content] }.join(' ')
      expect(flat).to include('[REDACTED]')
      expect(flat).not_to include('sk_live_abc123def456')
    end
  end
end
