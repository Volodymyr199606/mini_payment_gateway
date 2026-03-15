# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Replay::RequestReplayer do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }

  describe '.call' do
    it 'returns replay_not_possible when audit not found' do
      result = described_class.call(audit_id: -1)
      expect(result.replay_possible).to be false
      expect(result.reason_codes).to include('audit_not_found')
      expect(result.original_summary).to be_empty
    end

    it 'returns replay_not_possible when audit has no tool usage' do
      audit = AiRequestAudit.create!(
        request_id: 'nr1',
        endpoint: 'dashboard',
        agent_key: 'operational',
        merchant_id: merchant.id,
        tool_used: false,
        tool_names: []
      )
      result = described_class.call(audit_id: audit.id)
      expect(result.replay_possible).to be false
      expect(result.reason_codes).to include('no_tool_usage')
      expect(result.original_summary[:agent_key]).to eq('operational')
    end

    it 'runs replay and returns comparison when audit has tool usage and merchant' do
      audit = AiRequestAudit.create!(
        request_id: 'replay-r1',
        endpoint: 'dashboard',
        agent_key: 'tool:get_merchant_account',
        merchant_id: merchant.id,
        tool_used: true,
        tool_names: ['get_merchant_account']
      )
      result = described_class.call(audit_id: audit.id)
      expect(result.replay_possible).to be true
      expect(result.original_audit_id).to eq(audit.id)
      expect(result.original_summary[:tool_names]).to eq(['get_merchant_account'])
      expect(result.replay_summary).to be_a(Hash)
      expect(result.replay_summary[:tool_names]).to include('get_merchant_account')
      expect(result.matched_tool_usage).to be true
      expect(result.duration_ms).to be_a(Integer) if result.duration_ms
      expect(result.reason_codes).to include('intent_replay')
    end

    it 'does not expose sensitive fields in summaries' do
      audit = AiRequestAudit.create!(
        request_id: 'safe1',
        endpoint: 'dashboard',
        agent_key: 'tool:get_merchant_account',
        merchant_id: merchant.id,
        tool_used: true,
        tool_names: ['get_merchant_account'],
        error_message: 'Something failed'
      )
      result = described_class.call(audit_id: audit.id)
      h = result.to_h
      expect(h.keys).not_to include(:prompt, :api_key, :secret)
      keys = h[:original_summary].keys.map(&:to_s)
      expect(keys).not_to include('prompt', 'api_key', 'secret')
    end
  end
end
