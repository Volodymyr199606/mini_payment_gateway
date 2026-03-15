# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Replay::ReplayInputBuilder do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }

  describe '.call' do
    it 'marks replay impossible when audit has no tool usage' do
      audit = AiRequestAudit.create!(
        request_id: 'r1',
        endpoint: 'dashboard',
        agent_key: 'operational',
        merchant_id: merchant.id,
        tool_used: false,
        tool_names: []
      )
      result = described_class.call(audit)
      expect(result.possible?).to be false
      expect(result.reason_code).to eq('no_tool_usage')
    end

    it 'marks replay impossible when merchant_id is blank' do
      audit = AiRequestAudit.create!(
        request_id: 'r2',
        endpoint: 'dashboard',
        agent_key: 'tool:get_payment_intent',
        merchant_id: nil,
        tool_used: true,
        tool_names: ['get_payment_intent']
      )
      result = described_class.call(audit)
      expect(result.possible?).to be false
    end

    it 'builds resolved_intent and synthetic message for get_payment_intent' do
      audit = AiRequestAudit.create!(
        request_id: 'r3',
        endpoint: 'dashboard',
        agent_key: 'tool:get_payment_intent',
        merchant_id: merchant.id,
        tool_used: true,
        tool_names: ['get_payment_intent'],
        parsed_entities: { 'ids' => { 'payment_intent_id' => 42 } }
      )
      result = described_class.call(audit)
      expect(result.possible?).to be true
      expect(result.reason_code).to eq('intent_replay')
      expect(result.resolved_intent[:tool_name]).to eq('get_payment_intent')
      expect(result.resolved_intent[:args]).to eq({ payment_intent_id: 42 })
      expect(result.message).to include('42')
    end

    it 'builds resolved_intent for get_merchant_account with empty args' do
      audit = AiRequestAudit.create!(
        request_id: 'r4',
        endpoint: 'dashboard',
        agent_key: 'tool:get_merchant_account',
        merchant_id: merchant.id,
        tool_used: true,
        tool_names: ['get_merchant_account']
      )
      result = described_class.call(audit)
      expect(result.possible?).to be true
      expect(result.resolved_intent[:tool_name]).to eq('get_merchant_account')
      expect(result.resolved_intent[:args]).to eq({})
      expect(result.message).to be_present
    end
  end
end
