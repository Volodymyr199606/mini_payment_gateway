# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ComposedResponse / ResponseComposer output contract' do
  let(:valid_composition_modes) { %w[tool_only docs_only memory_docs hybrid_tool_docs memory_tool_docs] }

  describe 'ResponseComposer.call output' do
    it 'returns hash with reply, citations, agent_key, composition, contract_version in composition' do
      out = Ai::ResponseComposer.call(
        reply_text: 'Ok',
        citations: [],
        agent_key: 'support_faq',
        fallback_used: false
      )
      expect(out).to have_key(:reply)
      expect(out).to have_key(:citations)
      expect(out[:citations]).to be_a(Array)
      expect(out).to have_key(:agent_key)
      expect(out).to have_key(:composition)
      expect(out[:composition]).to be_a(Hash)
      expect(out[:composition][:contract_version]).to eq(Ai::Contracts::COMPOSED_RESPONSE_VERSION)
      expect(out[:composition][:composition_mode]).to be_present
    end

    it 'composition_mode is one of allowed values' do
      out = Ai::ResponseComposer.call(
        reply_text: 'Done',
        citations: [],
        agent_key: 'tool:get_ledger_summary',
        tool_name: 'get_ledger_summary',
        tool_result: { total: 100 },
        fallback_used: false
      )
      mode = out.dig(:composition, :composition_mode)
      AiContractHelpers.assert_enum!(
        mode,
        valid_composition_modes,
        contract_name: 'ResponseComposer',
        field_name: 'composition_mode'
      )
    end

    it 'does not expose sensitive fields' do
      out = Ai::ResponseComposer.call(reply_text: 'Safe', citations: [], agent_key: 'support_faq', fallback_used: false)
      AiContractHelpers.assert_no_forbidden_keys!(out, contract_name: 'ResponseComposer')
      AiContractHelpers.assert_no_forbidden_keys!(out[:composition] || {}, contract_name: 'ResponseComposer.composition')
    end
  end

  describe 'ComposedResponse contract' do
    it 'to_h includes composition.contract_version' do
      cr = Ai::Contracts::ComposedResponse.new(
        reply: 'x',
        agent_key: 'operational',
        composition: { composition_mode: 'docs_only' }
      )
      h = cr.to_h
      expect(h[:composition][:contract_version]).to eq(Ai::Contracts::COMPOSED_RESPONSE_VERSION)
    end
  end
end
