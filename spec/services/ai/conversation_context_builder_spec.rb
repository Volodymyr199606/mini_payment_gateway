# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::ConversationContextBuilder do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }
  let(:session) { merchant.ai_chat_sessions.create! }

  def add_message(role, content)
    session.ai_chat_messages.create!(role: role, content: content, merchant_id: merchant.id)
  end

  describe '.call' do
    it 'returns summary_text, recent_messages, user_preferences, open_tasks_or_followups, current_topic' do
      result = described_class.call(session, max_turns: 8)
      expect(result).to have_key(:summary_text)
      expect(result).to have_key(:recent_messages)
      expect(result).to have_key(:user_preferences)
      expect(result).to have_key(:open_tasks_or_followups)
      expect(result).to have_key(:current_topic)
      expect(result[:summary_text]).to eq('')
      expect(result[:recent_messages]).to eq([])
    end

    it 'uses session summary_text when present' do
      session.update!(summary_text: 'User asked about refunds.')
      result = described_class.call(session, max_turns: 8)
      expect(result[:summary_text]).to eq('User asked about refunds.')
    end

    it 'extracts user_preferences and open_tasks from structured summary' do
      summary = <<~TEXT
        ## Current topic
        - Refunds
        ## Facts
        - User asked about refunds.
        ## User preferences
        - Prefers email.
        ## Open tasks
        - Verify webhook.
      TEXT
      session.update!(summary_text: summary)
      add_message('user', 'Follow up')
      result = described_class.call(session, max_turns: 8)
      expect(result[:user_preferences]).to include('Prefers email')
      expect(result[:open_tasks_or_followups]).to include('Verify webhook')
      expect(result[:current_topic]).to include('Refunds')
    end

    it 'detects current_topic from recent messages when not in summary' do
      add_message('user', 'How do I configure webhooks for event notifications?')
      add_message('assistant', 'You can set up a webhook URL...')
      result = described_class.call(session, max_turns: 8)
      expect(result[:current_topic]).to eq('webhooks')
    end
  end

  describe 'recent_messages ordering' do
    it 'returns messages in chronological order (oldest first)' do
      add_message('user', 'First')
      add_message('assistant', 'First reply')
      add_message('user', 'Second')

      result = described_class.call(session, max_turns: 10)
      msgs = result[:recent_messages]
      expect(msgs.size).to eq(3)
      expect(msgs[0]).to eq({ role: 'user', content: 'First' })
      expect(msgs[1]).to eq({ role: 'assistant', content: 'First reply' })
      expect(msgs[2]).to eq({ role: 'user', content: 'Second' })
    end
  end

  describe 'recent_messages truncation' do
    it 'returns only the last max_turns messages' do
      5.times do |i|
        add_message('user', "User #{i}")
        add_message('assistant', "Assistant #{i}")
      end

      result = described_class.call(session, max_turns: 4)
      msgs = result[:recent_messages]
      expect(msgs.size).to eq(4)
      # Last 4: Assistant 3, User 4, Assistant 4 (and one more - last 4 by desc then reverse)
      expect(msgs.map { |m| m[:content] }).to eq(['Assistant 3', 'User 4', 'Assistant 4'].tap { |a| a.unshift('User 3') if a.size < 4 })
      # Actually: chronological last 4 = [User 3, Assistant 3, User 4, Assistant 4]
      expect(msgs.map { |m| m[:content] }).to eq(['User 3', 'Assistant 3', 'User 4', 'Assistant 4'])
    end

    it 'defaults to 8 messages when max_turns not given' do
      10.times { |i| add_message('user', "Msg #{i}") }

      result = described_class.call(session)
      expect(result[:recent_messages].size).to eq(8)
      expect(result[:recent_messages].map { |m| m[:content] }).to eq(
        ['Msg 2', 'Msg 3', 'Msg 4', 'Msg 5', 'Msg 6', 'Msg 7', 'Msg 8', 'Msg 9']
      )
    end
  end

  describe 'role filtering' do
    it 'excludes system messages, only includes user and assistant in chronological order' do
      add_message('user', 'U1')
      add_message('system', 'S1')
      add_message('assistant', 'A1')

      result = described_class.call(session, max_turns: 10)
      msgs = result[:recent_messages]
      expect(msgs.size).to eq(2)
      expect(msgs.map { |m| m[:role] }).to eq(%w[user assistant])
      expect(msgs.map { |m| m[:content] }).to eq(%w[U1 A1])
    end
  end

  describe '#to_groq_messages' do
    it 'returns array of { role:, content: } suitable for GroqClient' do
      add_message('user', 'Hello')
      add_message('assistant', 'Hi there')

      builder = described_class.new(session, max_turns: 10)
      groq = builder.to_groq_messages
      expect(groq).to eq([
        { role: 'user', content: 'Hello' },
        { role: 'assistant', content: 'Hi there' }
      ])
    end

    it 'matches recent_messages order and truncation' do
      3.times do |i|
        add_message('user', "U#{i}")
        add_message('assistant', "A#{i}")
      end

      builder = described_class.new(session, max_turns: 3)
      expect(builder.to_groq_messages.size).to eq(3)
      expect(builder.to_groq_messages.map { |m| m[:content] }).to eq(
        builder.call[:recent_messages].map { |m| m[:content] }
      )
    end
  end
end
