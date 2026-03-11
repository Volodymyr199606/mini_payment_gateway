# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Tools::Executor do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }
  let(:context) { { merchant_id: merchant.id, request_id: 'test-req' } }

  before do
    allow(Ai::Observability::EventLogger).to receive(:log_tool_call)
  end

  describe '.call' do
    it 'returns structured error for unknown tool' do
      result = described_class.call(tool_name: 'unknown', args: {}, context: context)
      expect(result[:success]).to be false
      expect(result[:error_code]).to eq('unknown_tool')
      expect(result[:tool_name]).to eq('unknown')
    end

    it 'returns structured error for invalid args' do
      result = described_class.call(
        tool_name: 'get_payment_intent',
        args: {},
        context: context
      )
      expect(result[:success]).to be false
      expect(result[:error]).to include('payment_intent_id')
    end

    it 'returns success and data for get_merchant_account' do
      result = described_class.call(
        tool_name: 'get_merchant_account',
        args: {},
        context: context
      )
      expect(result[:success]).to be true
      expect(result[:data][:id]).to eq(merchant.id)
      expect(result[:data][:name]).to eq(merchant.name)
    end

    it 'logs tool call with audit metadata' do
      described_class.call(tool_name: 'get_merchant_account', args: {}, context: context)
      expect(Ai::Observability::EventLogger).to have_received(:log_tool_call).with(
        hash_including(
          merchant_id: merchant.id,
          tool_name: 'get_merchant_account',
          success: true
        )
      )
    end

    it 'enforces merchant scoping for get_payment_intent' do
      pi = merchant.payment_intents.create!(
        customer_id: merchant.customers.create!(email: 'c@x.com', merchant_id: merchant.id).id,
        amount_cents: 1000,
        currency: 'USD'
      )
      other_merchant = create_merchant_with_api_key(name: 'Other').first
      result = described_class.call(
        tool_name: 'get_payment_intent',
        args: { payment_intent_id: pi.id },
        context: { merchant_id: other_merchant.id }
      )
      expect(result[:success]).to be false
      expect(result[:error]).to include('not found')
    end
  end
end
