# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Agents::ReconciliationAgent do
  let(:context_text) { "Reconciliation would match ledger entries to settlement. This gateway does not implement reconciliation yet; design guidance only." }
  let(:citations) { [{ file: 'docs/ARCHITECTURE.md', heading: 'Reconciliation', anchor: 'reconciliation', excerpt: 'Not implemented.' }] }

  describe '#call' do
    it 'returns non-empty reply text' do
      client = instance_double(Ai::GroqClient, chat: { content: 'Reconciliation is not implemented. It would involve matching ledger to settlement. See docs.', model_used: 'test', fallback_used: false })
      allow(Ai::GroqClient).to receive(:new).and_return(client)

      agent = described_class.new(message: 'How does reconciliation work?', context_text: context_text, citations: citations)
      out = agent.call

      expect(out.reply_text).to be_a(String)
      expect(out.reply_text).to be_present
    end

    it 'returns citations array (from retrieval)' do
      client = instance_double(Ai::GroqClient, chat: { content: 'Not implemented yet.', model_used: 'test', fallback_used: false })
      allow(Ai::GroqClient).to receive(:new).and_return(client)

      agent = described_class.new(message: 'Reconciliation?', context_text: context_text, citations: citations)
      out = agent.call

      expect(out.citations).to eq(citations)
      expect(out.citations).to be_a(Array)
    end

    it 'uses retrieval context in prompt sent to Groq' do
      chat_messages = nil
      client = instance_double(Ai::GroqClient)
      allow(client).to receive(:chat) do |messages:, **_kwargs|
        chat_messages = messages
        { content: 'Reconciliation is not implemented.', model_used: 'test', fallback_used: false }
      end
      allow(Ai::GroqClient).to receive(:new).and_return(client)

      agent = described_class.new(message: 'Reconciliation?', context_text: context_text, citations: citations)
      agent.call

      system_content = chat_messages.find { |m| (m[:role] || m['role']) == 'system' }&.dig(:content) || chat_messages.find { |m| (m[:role] || m['role']) == 'system' }&.dig('content')
      expect(system_content).to include(context_text)
      expect(system_content).to include('reconciliation')
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
