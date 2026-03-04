# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Guardrails::Pipeline do
  let(:citations) { [{ file: 'docs/REFUNDS_API.md', heading: 'Refunds', anchor: 'refunds' }] }
  let(:context_with_docs) { { context_text: 'A' * 100, citations: citations } }
  let(:empty_context) { { context_text: nil, citations: [] } }
  let(:built_messages) { [{ role: 'system', content: 'You are helpful.' }, { role: 'user', content: 'Hi' }] }
  let(:input) { { built_messages: built_messages } }

  describe 'empty retrieval skips LLM' do
    it 'short-circuits when context is empty and result is nil (no LLM call)' do
      llm_called = false
      llm_call = ->(_) { llm_called = true; { content: 'x', model_used: 'y', fallback_used: false } }

      out = described_class.call(
        input: input,
        result: nil,
        context: empty_context,
        llm_call: llm_call
      )

      expect(out[:short_circuit]).to be true
      expect(out[:reply_text]).to include("I couldn't find this in the docs")
      expect(out[:reply_text]).to include("Where to look next:")
      expect(out[:fallback_used]).to be true
      expect(llm_called).to be false
    end

    it 'short-circuits when context_text is below threshold' do
      short_context = { context_text: 'Short.', citations: [] }

      out = described_class.call(input: input, result: nil, context: short_context)

      expect(out[:short_circuit]).to be true
      expect(out[:reply_text]).to include("I couldn't find this in the docs")
    end

    it 'does not short-circuit when context is above threshold and result is nil' do
      out = described_class.call(
        input: input,
        result: nil,
        context: context_with_docs
      )

      expect(out[:short_circuit]).not_to be true
      expect(out[:reply_text]).to eq('')
    end
  end

  describe 'citation re-ask triggers at most once' do
    it 'calls llm_call once when reply has no citation reference' do
      call_count = 0
      llm_call = ->(messages) {
        call_count += 1
        user_messages = messages.select { |m| m[:role] == 'user' }
        last_user_content = user_messages.last&.dig(:content)
        content = (last_user_content == 'Answer again and cite sources.') ? 'See docs/REFUNDS_API.md.' : 'Just a reply.'
        { content: content, model_used: 'llama', fallback_used: false }
      }

      result = { content: 'Just a reply with no citation.', model_used: 'x', fallback_used: false }
      out = described_class.call(
        input: input,
        result: result,
        context: context_with_docs,
        llm_call: llm_call
      )

      expect(call_count).to eq(1)
      expect(out[:guardrail_reask]).to be true
      expect(out[:reply_text]).to include('REFUNDS_API')
    end

    it 'does not call llm_call when reply already references a citation' do
      call_count = 0
      llm_call = ->(_) { call_count += 1; { content: 'x', model_used: 'y', fallback_used: false } }

      result = { content: 'See docs/REFUNDS_API.md for details.', model_used: 'llama', fallback_used: false }
      out = described_class.call(
        input: input,
        result: result,
        context: context_with_docs,
        llm_call: llm_call
      )

      expect(call_count).to eq(0)
      expect(out[:guardrail_reask]).to be false
    end
  end

  describe 'secret leak redaction' do
    it 'redacts obvious tokens and prepends warning' do
      # Use a pattern MessageSanitizer matches: api_key= with 20+ chars
      secret = 'api_key=abcdefghijklmnopqrstuvwxyz12345'
      result = {
        content: "Your #{secret} should be kept safe.",
        model_used: 'llama',
        fallback_used: false
      }

      out = described_class.call(
        input: input,
        result: result,
        context: context_with_docs
      )

      expect(out[:short_circuit]).not_to be true
      expect(out[:reply_text]).to include(Ai::MessageSanitizer::REDACT_PLACEHOLDER)
      expect(out[:reply_text]).not_to include(secret)
      expect(out[:reply_text]).to include('partially redacted')
    end

    it 'does not alter reply when no sensitive patterns found' do
      result = {
        content: 'Refunds use POST /refunds. See the docs.',
        model_used: 'llama',
        fallback_used: false
      }

      out = described_class.call(
        input: input,
        result: result,
        context: context_with_docs
      )

      expect(out[:reply_text]).to eq('Refunds use POST /refunds. See the docs.')
      expect(out[:reply_text]).not_to include(Ai::MessageSanitizer::REDACT_PLACEHOLDER)
    end
  end
end
