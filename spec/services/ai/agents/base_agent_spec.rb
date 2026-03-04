# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Agents::BaseAgent do
  # Use SupportFaqAgent as a concrete subclass for testing base behavior
  let(:agent_class) { Ai::Agents::SupportFaqAgent }
  # Must be >= BaseAgent::LOW_CONTEXT_THRESHOLD (80) so agent calls Groq in reply-format examples
  let(:context_text) { "docs/REFUNDS_API.md: Refunds are processed via POST /refunds. Use the idempotency key when retrying. Refunds appear in the ledger." }
  let(:citations) { [{ file: 'docs/REFUNDS_API.md', heading: 'Refunds', anchor: 'refunds', excerpt: '...' }] }

  describe 'reply format' do
    it 'does not include filler phrases like "provided context" or "based on context"' do
      reply_with_filler = "According to the provided context, refunds use POST. Based on context, we can infer this."
      client = instance_double(Ai::GroqClient, chat: { content: reply_with_filler, model_used: 'test', fallback_used: false })
      allow(Ai::GroqClient).to receive(:new).and_return(client)

      agent = agent_class.new(message: 'How do refunds work?', context_text: context_text, citations: citations)
      out = agent.call

      expect(out.reply_text).not_to match(/provided context/i)
      expect(out.reply_text).not_to match(/based on context/i)
      expect(out.reply_text).not_to match(/we can infer/i)
    end

    it 'does not contain inline [docs/...] citation strings' do
      reply_with_inline = "Refunds use POST. See [docs/REFUNDS_API.md] for details."
      client = instance_double(Ai::GroqClient, chat: { content: reply_with_inline, model_used: 'test', fallback_used: false })
      allow(Ai::GroqClient).to receive(:new).and_return(client)

      agent = agent_class.new(message: 'How do refunds work?', context_text: context_text, citations: citations)
      out = agent.call

      expect(out.reply_text).not_to match(/\[docs?\/[^\]]*\]/i)
    end

    it 'strips parenthetical citation refs like (docs/REFUNDS_API.md)' do
      reply_with_paren = "Refunds use POST (docs/REFUNDS_API.md)."
      client = instance_double(Ai::GroqClient, chat: { content: reply_with_paren, model_used: 'test', fallback_used: false })
      allow(Ai::GroqClient).to receive(:new).and_return(client)

      agent = agent_class.new(message: 'How do refunds work?', context_text: context_text, citations: citations)
      out = agent.call

      expect(out.reply_text).not_to match(/\(docs?\/[^)]*\)/i)
      expect(out.reply_text).to include('Refunds use POST')
    end

    it 'returns citations as structured array' do
      client = instance_double(Ai::GroqClient, chat: { content: 'Refunds use POST.', model_used: 'test', fallback_used: false })
      allow(Ai::GroqClient).to receive(:new).and_return(client)

      agent = agent_class.new(message: 'How do refunds work?', context_text: context_text, citations: citations)
      out = agent.call

      expect(out.citations).to eq(citations)
      expect(out.citations).to be_a(Array)
      expect(out.citations.first).to include(file: 'docs/REFUNDS_API.md', heading: 'Refunds')
    end
  end

  describe 'low context (empty or too small)' do
    it 'returns deterministic fallback and does not call Groq when context is empty' do
      client = instance_double(Ai::GroqClient, chat: { content: 'Never used', model_used: nil, fallback_used: false })
      allow(Ai::GroqClient).to receive(:new).and_return(client)

      agent = agent_class.new(message: 'How do refunds work?', context_text: '', citations: [])
      out = agent.call

      expect(out.reply_text).to include("I couldn't find this in the docs")
      expect(out.reply_text).to include("Where to look next:")
      expect(out.reply_text).to include("docs/REFUNDS_API.md")
      expect(out.fallback_used).to be true
      expect(out.model_used).to be_nil
      expect(out.citations).to eq([])
      expect(client).not_to have_received(:chat)
    end

    it 'returns deterministic fallback when context is below threshold' do
      client = instance_double(Ai::GroqClient, chat: { content: 'Never used', model_used: nil, fallback_used: false })
      allow(Ai::GroqClient).to receive(:new).and_return(client)

      agent = agent_class.new(message: 'Foo?', context_text: 'Short.', citations: [])
      out = agent.call

      expect(out.reply_text).to include("I couldn't find this in the docs")
      expect(out.reply_text).to include("Where to look next:")
      expect(out.fallback_used).to be true
      expect(client).not_to have_received(:chat)
    end

    it 'calls Groq when context is above threshold' do
      client = instance_double(Ai::GroqClient, chat: { content: 'Refunds use POST. See docs/REFUNDS_API.md.', model_used: 'test', fallback_used: false })
      allow(Ai::GroqClient).to receive(:new).and_return(client)

      agent = agent_class.new(message: 'How do refunds work?', context_text: context_text, citations: citations)
      agent.call

      expect(client).to have_received(:chat).once
    end
  end

  describe 'empty retrieval guardrail' do
    it 'returns safe fallback and suggests where to look when retriever returns no sections' do
      client = instance_double(Ai::GroqClient, chat: { content: 'Never used', model_used: nil, fallback_used: false })
      allow(Ai::GroqClient).to receive(:new).and_return(client)

      agent = agent_class.new(message: 'Something obscure', context_text: nil, citations: [])
      out = agent.call

      expect(out.reply_text).to include("I couldn't find this in the docs")
      expect(out.reply_text).to include("Here's what I can say generally")
      expect(out.reply_text).to include("Where to look next:")
      expect(out.reply_text).to match(/Dashboard|docs\/.*\.md/)
      expect(out.citations).to eq([])
      expect(out.fallback_used).to be true
      expect(client).not_to have_received(:chat)
    end
  end

  describe 'citation enforcement' do
    it 're-asks once with "Answer again and cite sources." when reply has no citation reference' do
      first_reply = "Refunds are done via API. Use idempotency."
      second_reply = "Refunds use POST. See docs/REFUNDS_API.md for details."
      chat_messages_list = []
      client = instance_double(Ai::GroqClient)
      allow(client).to receive(:chat) do |messages:, **|
        chat_messages_list << messages
        if chat_messages_list.size == 1
          { content: first_reply, model_used: 'llama', fallback_used: false }
        else
          { content: second_reply, model_used: 'llama', fallback_used: false }
        end
      end
      allow(Ai::GroqClient).to receive(:new).and_return(client)

      agent = agent_class.new(message: 'How do refunds work?', context_text: context_text, citations: citations)
      out = agent.call

      expect(out.reply_text).to include('REFUNDS_API')
      expect(out.reply_text).not_to eq(first_reply)
      expect(chat_messages_list.size).to eq(2)
      expect(chat_messages_list.last.last[:content]).to eq('Answer again and cite sources.')
    end

    it 'does not re-ask when reply already references a citation' do
      reply_with_cite = "Refunds use POST. See docs/REFUNDS_API.md."
      client = instance_double(Ai::GroqClient, chat: { content: reply_with_cite, model_used: 'llama', fallback_used: false })
      allow(Ai::GroqClient).to receive(:new).and_return(client)

      agent = agent_class.new(message: 'How do refunds work?', context_text: context_text, citations: citations)
      out = agent.call

      expect(out.reply_text).to include('REFUNDS_API')
      expect(client).to have_received(:chat).once
    end
  end

  describe 'AgentResult contract' do
    it 'returns an Ai::AgentResult with reply_text, citations, agent_key, model_used, fallback_used, metadata' do
      client = instance_double(Ai::GroqClient, chat: { content: 'Refunds use POST. See docs/REFUNDS_API.md.', model_used: 'llama', fallback_used: false })
      allow(Ai::GroqClient).to receive(:new).and_return(client)

      agent = agent_class.new(message: 'How do refunds work?', context_text: context_text, citations: citations)
      out = agent.call

      expect(out).to be_a(Ai::AgentResult)
      expect(out.reply_text).to be_a(String)
      expect(out.citations).to eq(citations)
      expect(out.agent_key).to eq('support_faq')
      expect(out.model_used).to eq('llama')
      expect(out.fallback_used).to eq(false)
      expect(out.metadata).to include(docs_used_count: 1, summary_used: false, guardrail_reask: false)
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
