# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Policy::Decision do
  describe '.allow' do
    it 'returns allowed decision with optional metadata' do
      d = described_class.allow
      expect(d.allowed?).to be true
      expect(d.denied?).to be false
      expect(d.reason_code).to be_nil
      expect(d.safe_message).to be_nil
      expect(d.metadata).to eq({})
    end

    it 'accepts metadata' do
      d = described_class.allow(metadata: { tool_name: 'get_payment_intent' })
      expect(d.allowed?).to be true
      expect(d.metadata).to eq({ tool_name: 'get_payment_intent' })
    end
  end

  describe '.deny' do
    it 'returns denied decision with reason_code' do
      d = described_class.deny(reason_code: 'record_not_owned')
      expect(d.allowed?).to be false
      expect(d.denied?).to be true
      expect(d.reason_code).to eq('record_not_owned')
      expect(d.metadata).to eq({})
    end

    it 'accepts safe_message and metadata' do
      d = described_class.deny(
        reason_code: 'merchant_required',
        safe_message: 'Merchant context required',
        metadata: { entity_type: 'payment_intent' }
      )
      expect(d.denied?).to be true
      expect(d.safe_message).to eq('Merchant context required')
      expect(d.metadata).to eq({ entity_type: 'payment_intent' })
    end
  end

  describe 'decision_type' do
    it '.allow accepts optional decision_type' do
      d = described_class.allow(decision_type: :tool, metadata: {})
      expect(d.allowed?).to be true
      expect(d.decision_type).to eq(:tool)
    end

    it '.deny accepts optional decision_type' do
      d = described_class.deny(reason_code: 'no_intent', decision_type: :orchestration)
      expect(d.denied?).to be true
      expect(d.decision_type).to eq(:orchestration)
    end
  end
end
