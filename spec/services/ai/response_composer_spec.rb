# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::ResponseComposer do
  describe '.call' do
    it 'returns reply, citations, agent_key, model_used, fallback_used, data, and composition' do
      result = described_class.call(
        reply_text: 'Hello',
        citations: [],
        agent_key: 'support_faq'
      )
      expect(result).to include(
        reply: 'Hello',
        citations: [],
        agent_key: 'support_faq',
        fallback_used: false
      )
      expect(result[:composition]).to be_a(Hash)
    end

    context 'docs-only composition' do
      it 'sets composition_mode to docs_only when citations present and no tool/memory' do
        citations = [{ file: 'PAYMENT_LIFECYCLE.md', heading: 'States' }]
        result = described_class.call(
          reply_text: 'Payment intents have states.',
          citations: citations,
          agent_key: 'operational'
        )
        expect(result[:reply]).to eq('Payment intents have states.')
        expect(result[:citations]).to eq(citations)
        expect(result[:composition][:composition_mode]).to eq('docs_only')
        expect(result[:composition][:used_tool_data]).to be(false)
        expect(result[:composition][:used_doc_context]).to be(true)
        expect(result[:composition][:used_memory_context]).to be(false)
        expect(result[:composition][:citations_count]).to eq(1)
        expect(result[:composition][:deterministic_fields_used]).to eq([])
      end
    end

    context 'tool-only composition' do
      it 'sets composition_mode to tool_only when tool_name present and no citations' do
        result = described_class.call(
          reply_text: 'Payment pi_123 is requires_capture.',
          citations: [],
          agent_key: 'tool:get_payment_intent',
          tool_name: 'get_payment_intent',
          tool_result: { id: 'pi_123', status: 'requires_capture' }
        )
        expect(result[:reply]).to eq('Payment pi_123 is requires_capture.')
        expect(result[:citations]).to eq([])
        expect(result[:composition][:composition_mode]).to eq('tool_only')
        expect(result[:composition][:used_tool_data]).to be(true)
        expect(result[:composition][:used_doc_context]).to be(false)
        expect(result[:composition][:used_memory_context]).to be(false)
        expect(result[:composition][:citations_count]).to eq(0)
        expect(result[:composition][:deterministic_fields_used]).to include('payment_intent')
      end

      it 'does not fabricate citations for tool data' do
        result = described_class.call(
          reply_text: 'Ledger total: $100',
          citations: [],
          agent_key: 'tool:get_ledger_summary',
          tool_name: 'get_ledger_summary',
          tool_result: { net: 100 }
        )
        expect(result[:citations]).to eq([])
        expect(result[:composition][:citations_count]).to eq(0)
      end
    end

    context 'hybrid tool + docs composition' do
      it 'sets composition_mode to hybrid_tool_docs when both tool and citations present' do
        citations = [{ file: 'PAYMENT_LIFECYCLE.md', heading: 'Capture' }]
        result = described_class.call(
          reply_text: 'Pi_123 is requires_capture. According to docs, that means authorized but not captured.',
          citations: citations,
          agent_key: 'tool:get_payment_intent',
          tool_name: 'get_payment_intent',
          tool_result: { id: 'pi_123', status: 'requires_capture' }
        )
        expect(result[:citations]).to eq(citations)
        expect(result[:composition][:composition_mode]).to eq('hybrid_tool_docs')
        expect(result[:composition][:used_tool_data]).to be(true)
        expect(result[:composition][:used_doc_context]).to be(true)
        expect(result[:composition][:citations_count]).to eq(1)
      end
    end

    context 'memory + docs composition' do
      it 'sets composition_mode to memory_docs when memory used and citations present' do
        citations = [{ file: 'METRICS.md', heading: 'Volume' }]
        result = described_class.call(
          reply_text: 'Based on our conversation, net volume is defined in METRICS.',
          citations: citations,
          agent_key: 'support_faq',
          memory_used: true
        )
        expect(result[:composition][:composition_mode]).to eq('memory_docs')
        expect(result[:composition][:used_tool_data]).to be(false)
        expect(result[:composition][:used_doc_context]).to be(true)
        expect(result[:composition][:used_memory_context]).to be(true)
      end
    end

    context 'deterministic agent (reporting_calculation)' do
      it 'sets used_tool_data true and deterministic_fields_used for ledger_summary' do
        result = described_class.call(
          reply_text: 'Net volume today: $500',
          citations: [],
          agent_key: 'reporting_calculation',
          data: { ledger_summary: { net_volume: 500 } }
        )
        expect(result[:composition][:composition_mode]).to eq('tool_only')
        expect(result[:composition][:used_tool_data]).to be(true)
        expect(result[:composition][:deterministic_fields_used]).to eq(['ledger_summary'])
      end

      it 'treats reporting_calculation as deterministic without tool_name' do
        result = described_class.call(
          reply_text: 'Summary.',
          citations: [],
          agent_key: 'reporting_calculation'
        )
        expect(result[:composition][:used_tool_data]).to be(true)
      end
    end

    context 'composition metadata' do
      it 'exposes all composition fields for observability' do
        result = described_class.call(
          reply_text: 'Ok',
          citations: [{ file: 'a.md' }],
          agent_key: 'operational',
          memory_used: true
        )
        comp = result[:composition]
        expect(comp.keys).to contain_exactly(
          :used_tool_data,
          :used_doc_context,
          :used_memory_context,
          :citations_count,
          :deterministic_fields_used,
          :composition_mode,
          :contract_version
        )
      end

      it 'merges explanation_metadata into composition when provided' do
        result = described_class.call(
          reply_text: 'Payment intent 42 is authorized.',
          citations: [],
          agent_key: 'tool:get_payment_intent',
          tool_name: 'get_payment_intent',
          explanation_metadata: {
            deterministic_explanation_used: true,
            explanation_type: 'payment_intent',
            explanation_key: 'authorized',
            llm_skipped_due_to_template: true
          }
        )
        comp = result[:composition]
        expect(comp[:deterministic_explanation_used]).to be true
        expect(comp[:explanation_type]).to eq('payment_intent')
        expect(comp[:explanation_key]).to eq('authorized')
        expect(comp[:llm_skipped_due_to_template]).to be true
      end
    end
  end
end
