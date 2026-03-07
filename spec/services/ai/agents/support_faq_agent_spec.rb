# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Agents::SupportFaqAgent do
  # Must be >= BaseAgent::LOW_CONTEXT_THRESHOLD (80) so agent calls Groq
  let(:context_text) { "docs/REFUNDS_API.md: Refunds are processed via POST /refunds. Use the idempotency key when retrying. Refunds appear in the ledger." }
  let(:citations) { [{ file: 'docs/REFUNDS_API.md', heading: 'Refunds', anchor: 'refunds', excerpt: 'Refunds are processed via POST.' }] }

  describe '#call' do
    it 'returns non-empty reply text' do
      client = instance_double(Ai::GroqClient, chat: { content: 'Refunds use POST. See docs/REFUNDS_API.md.', model_used: 'test', fallback_used: false })
      allow(Ai::GroqClient).to receive(:new).and_return(client)

      agent = described_class.new(message: 'How do refunds work?', context_text: context_text, citations: citations)
      out = agent.call

      expect(out.reply_text).to be_a(String)
      expect(out.reply_text).to be_present
    end

    it 'returns citations array (from retrieval)' do
      client = instance_double(Ai::GroqClient, chat: { content: 'Refunds use POST.', model_used: 'test', fallback_used: false })
      allow(Ai::GroqClient).to receive(:new).and_return(client)

      agent = described_class.new(message: 'How do refunds work?', context_text: context_text, citations: citations)
      out = agent.call

      expect(out.citations).to eq(citations)
      expect(out.citations).to be_a(Array)
    end

    it 'uses retrieval context in prompt sent to Groq' do
      chat_messages = nil
      client = instance_double(Ai::GroqClient)
      allow(client).to receive(:chat) do |messages:, **_kwargs|
        chat_messages = messages
        { content: 'Refunds use POST.', model_used: 'test', fallback_used: false }
      end
      allow(Ai::GroqClient).to receive(:new).and_return(client)

      agent = described_class.new(message: 'How do refunds work?', context_text: context_text, citations: citations)
      agent.call

      system_content = chat_messages.find { |m| (m[:role] || m['role']) == 'system' }&.dig(:content) || chat_messages.find { |m| (m[:role] || m['role']) == 'system' }&.dig('content')
      expect(system_content).to include(context_text)
      expect(system_content).to include('REFUNDS_API')
    end

    it 'returns empty citations when empty retrieval guard triggers' do
      client = instance_double(Ai::GroqClient, chat: { content: 'Never used', model_used: nil, fallback_used: false })
      allow(Ai::GroqClient).to receive(:new).and_return(client)

      agent = described_class.new(message: 'Obscure?', context_text: '', citations: [])
      out = agent.call

      expect(out.reply_text).to be_present
      expect(out.citations).to eq([])
      expect(out.fallback_used).to be true
    end
  end
end
