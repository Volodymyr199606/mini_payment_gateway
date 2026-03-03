# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Agents::BaseAgent do
  # Use SupportFaqAgent as a concrete subclass for testing base behavior
  let(:agent_class) { Ai::Agents::SupportFaqAgent }
  let(:context_text) { "docs/REFUNDS_API.md: Refunds are processed via POST /refunds." }
  let(:citations) { [{ file: 'docs/REFUNDS_API.md', heading: 'Refunds', anchor: 'refunds', excerpt: '...' }] }

  describe 'reply format' do
    it 'does not include filler phrases like "provided context" or "based on context"' do
      reply_with_filler = "According to the provided context, refunds use POST. Based on context, we can infer this."
      client = instance_double(Ai::GroqClient, chat: { content: reply_with_filler, model_used: 'test', fallback_used: false })
      allow(Ai::GroqClient).to receive(:new).and_return(client)

      agent = agent_class.new(message: 'How do refunds work?', context_text: context_text, citations: citations)
      out = agent.call

      expect(out[:reply]).not_to match(/provided context/i)
      expect(out[:reply]).not_to match(/based on context/i)
      expect(out[:reply]).not_to match(/we can infer/i)
    end

    it 'does not contain inline [docs/...] citation strings' do
      reply_with_inline = "Refunds use POST. See [docs/REFUNDS_API.md] for details."
      client = instance_double(Ai::GroqClient, chat: { content: reply_with_inline, model_used: 'test', fallback_used: false })
      allow(Ai::GroqClient).to receive(:new).and_return(client)

      agent = agent_class.new(message: 'How do refunds work?', context_text: context_text, citations: citations)
      out = agent.call

      expect(out[:reply]).not_to match(/\[docs?\/[^\]]*\]/i)
    end

    it 'strips parenthetical citation refs like (docs/REFUNDS_API.md)' do
      reply_with_paren = "Refunds use POST (docs/REFUNDS_API.md)."
      client = instance_double(Ai::GroqClient, chat: { content: reply_with_paren, model_used: 'test', fallback_used: false })
      allow(Ai::GroqClient).to receive(:new).and_return(client)

      agent = agent_class.new(message: 'How do refunds work?', context_text: context_text, citations: citations)
      out = agent.call

      expect(out[:reply]).not_to match(/\(docs?\/[^)]*\)/i)
      expect(out[:reply]).to include('Refunds use POST')
    end

    it 'returns citations as structured array' do
      client = instance_double(Ai::GroqClient, chat: { content: 'Refunds use POST.', model_used: 'test', fallback_used: false })
      allow(Ai::GroqClient).to receive(:new).and_return(client)

      agent = agent_class.new(message: 'How do refunds work?', context_text: context_text, citations: citations)
      out = agent.call

      expect(out[:citations]).to eq(citations)
      expect(out[:citations]).to be_a(Array)
      expect(out[:citations].first).to include(file: 'docs/REFUNDS_API.md', heading: 'Refunds')
    end
  end

  describe '#strip_inline_citations' do
    it 'removes [docs/...] patterns' do
      agent = agent_class.new(message: 'x', context_text: 'x', citations: [])
      expect(agent.send(:strip_inline_citations, "Answer [docs/FOO.md] here.")).to eq("Answer here.")
    end

    it 'removes (docs/...) patterns' do
      agent = agent_class.new(message: 'x', context_text: 'x', citations: [])
      expect(agent.send(:strip_inline_citations, "Answer (docs/BAR.md) here.")).to eq("Answer here.")
    end
  end
end
