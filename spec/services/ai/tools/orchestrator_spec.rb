# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Tools::Orchestrator do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }

  before do
    allow(Ai::Observability::EventLogger).to receive(:log_tool_call)
  end

  describe '.invoke_if_applicable' do
    it 'returns invoked: false when no intent detected' do
      out = described_class.invoke_if_applicable(
        message: 'What is the refund policy?',
        merchant_id: merchant.id
      )
      expect(out[:invoked]).to be false
    end

    it 'returns invoked: true and formatted reply for my account' do
      out = described_class.invoke_if_applicable(
        message: 'Show my account info',
        merchant_id: merchant.id
      )
      expect(out[:invoked]).to be true
      expect(out[:tool_name]).to eq('get_merchant_account')
      expect(out[:reply_text]).to include(merchant.name)
    end

    it 'invokes at most one tool per call' do
      out = described_class.invoke_if_applicable(
        message: 'Show my account',
        merchant_id: merchant.id
      )
      expect(out[:invoked]).to be true
      expect(out[:result]).to be_present
      expect(out[:reply_text]).to be_present
    end

    it 'returns invoked: false when merchant_id blank' do
      out = described_class.invoke_if_applicable(
        message: 'Show my account',
        merchant_id: nil
      )
      expect(out[:invoked]).to be false
    end
  end
end
