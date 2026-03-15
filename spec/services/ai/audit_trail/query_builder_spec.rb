# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::AuditTrail::QueryBuilder do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }

  before do
    AiRequestAudit.create!(
      request_id: 'q1',
      endpoint: 'dashboard',
      agent_key: 'tool:get_payment_intent',
      merchant_id: merchant.id,
      composition_mode: 'tool_only',
      tool_used: true,
      tool_names: ['get_payment_intent'],
      success: true
    )
    AiRequestAudit.create!(
      request_id: 'q2',
      endpoint: 'api',
      agent_key: 'operational',
      merchant_id: nil,
      success: false,
      fallback_used: true
    )
  end

  describe '.call' do
    it 'returns recent audits by default' do
      rel = described_class.call(params: {}, limit: 10)
      expect(rel.count).to eq(2)
      expect(rel).to be_a(ActiveRecord::Relation)
    end

    it 'respects limit' do
      rel = described_class.call(params: {}, limit: 1)
      expect(rel.count).to eq(1)
    end

    it 'filters by merchant_id' do
      rel = described_class.call(params: { merchant_id: merchant.id }, limit: 100)
      expect(rel.pluck(:request_id)).to contain_exactly('q1')
    end

    it 'filters by agent_key' do
      rel = described_class.call(params: { agent_key: 'operational' }, limit: 100)
      expect(rel.pluck(:request_id)).to contain_exactly('q2')
    end

    it 'filters by fallback_only' do
      rel = described_class.call(params: { fallback_only: '1' }, limit: 100)
      expect(rel.pluck(:request_id)).to contain_exactly('q2')
    end

    it 'filters by failed_only' do
      rel = described_class.call(params: { failed_only: '1' }, limit: 100)
      expect(rel.pluck(:request_id)).to contain_exactly('q2')
    end

    it 'filters by tool_used true' do
      rel = described_class.call(params: { tool_used: '1' }, limit: 100)
      expect(rel.pluck(:request_id)).to contain_exactly('q1')
    end

    it 'filters by request_id search' do
      rel = described_class.call(params: { request_id: 'q2' }, limit: 100)
      expect(rel.pluck(:request_id)).to contain_exactly('q2')
    end
  end
end
