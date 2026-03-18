# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Audit payload contract' do
  describe 'RecordBuilder output (audit payload shape)' do
    it 'includes schema_version and stable keys expected by drill-down and replay' do
      record = Ai::AuditTrail::RecordBuilder.call(
        request_id: 'req-1',
        endpoint: 'dashboard',
        merchant_id: 1,
        agent_key: 'support_faq',
        composition: { composition_mode: 'docs_only' },
        tool_used: false,
        tool_names: [],
        success: true,
        execution_plan_metadata: {
          execution_mode: 'agent_full',
          retrieval_skipped: false,
          memory_skipped: false,
          retrieval_budget_reduced: false,
          contract_version: '1'
        }
      )
      expect(record).to have_key(:schema_version)
      expect(record[:schema_version]).to eq(Ai::Contracts::AUDIT_PAYLOAD_VERSION)
      # Keys consumed by DetailPresenter and ReplayInputBuilder
      expect(record).to have_key(:request_id)
      expect(record).to have_key(:merchant_id)
      expect(record).to have_key(:agent_key)
      expect(record).to have_key(:composition_mode)
      expect(record).to have_key(:tool_used)
      expect(record).to have_key(:tool_names)
      expect(record).to have_key(:execution_mode)
      expect(record).to have_key(:retrieval_skipped)
      expect(record).to have_key(:memory_skipped)
    end

    it 'does not persist prompt, api_key, or other sensitive keys' do
      record = Ai::AuditTrail::RecordBuilder.call(
        request_id: 'r1',
        endpoint: 'dashboard',
        merchant_id: 1,
        agent_key: 'support_faq',
        composition: {},
        tool_used: false,
        success: true
      )
      AiContractHelpers.assert_no_forbidden_keys!(record, contract_name: 'Audit payload')
    end
  end

  describe 'AuditPayload contract STABLE_KEYS' do
    it 'AuditPayload::STABLE_KEYS includes keys used by drill-down and replay' do
      # Subset that must be in STABLE_KEYS (drill-down and replay depend on these)
      expected = %w[
        request_id endpoint merchant_id agent_key composition_mode tool_used tool_names
        orchestration_used parsed_entities parsed_intent_hints authorization_denied tool_blocked_by_policy
      ]
      expected.each do |key|
        expect(Ai::Contracts::AuditPayload::STABLE_KEYS).to include(key),
          "AuditPayload::STABLE_KEYS should include #{key} for drill-down/replay"
      end
    end
  end
end
