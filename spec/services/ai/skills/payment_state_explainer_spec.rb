# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Skills::PaymentStateExplainer do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }
  let(:customer) { merchant.customers.create!(email: "cust_#{SecureRandom.hex(4)}@example.com") }

  describe '#execute' do
    it 'returns failure when merchant_id missing' do
      result = described_class.new.execute(context: {})
      expect(result.failure?).to be true
      expect(result.error_code).to eq('missing_context')
    end

    it 'returns failure when no entity provided' do
      result = described_class.new.execute(context: { merchant_id: merchant.id })
      expect(result.failure?).to be true
      expect(result.error_code).to eq('missing_entity')
    end

    it 'explains payment intent from id' do
      pi = merchant.payment_intents.create!(customer: customer, amount_cents: 1000, currency: 'USD', status: 'created')
      result = described_class.new.execute(context: { merchant_id: merchant.id, payment_intent_id: pi.id })
      expect(result.success).to be true
      expect(result.explanation).to include(pi.id.to_s)
      expect(result.explanation).to include('created')
      expect(result.explanation).to include('$10.00').or include('10.00')
      expect(result.data['explanation_type']).to eq('payment_intent')
      expect(result.data['explanation_key']).to eq('created')
      expect(result.deterministic).to be true
    end

    it 'explains captured payment intent' do
      pi = merchant.payment_intents.create!(customer: customer, amount_cents: 5000, currency: 'USD', status: 'captured')
      result = described_class.new.execute(context: { merchant_id: merchant.id, payment_intent_id: pi.id })
      expect(result.success).to be true
      expect(result.explanation).to include('captured')
    end

    it 'explains refunded payment intent when captured with refunds' do
      pi = merchant.payment_intents.create!(customer: customer, amount_cents: 5000, currency: 'USD', status: 'captured')
      pi.transactions.create!(kind: 'capture', status: 'succeeded', amount_cents: 5000, processor_ref: 'cap_1')
      pi.transactions.create!(kind: 'refund', status: 'succeeded', amount_cents: 2000, processor_ref: 'ref_1')
      result = described_class.new.execute(context: { merchant_id: merchant.id, payment_intent_id: pi.id })
      expect(result.success).to be true
      expect(result.explanation.downcase).to include('refund')
    end

    it 'explains transaction from id' do
      pi = merchant.payment_intents.create!(customer: customer, amount_cents: 3000, currency: 'USD', status: 'captured')
      txn = pi.transactions.create!(kind: 'capture', status: 'succeeded', amount_cents: 3000, processor_ref: 'ref_xyz')
      result = described_class.new.execute(context: { merchant_id: merchant.id, transaction_id: txn.id })
      expect(result.success).to be true
      expect(result.explanation).to include('capture')
      expect(result.explanation).to include('succeeded')
      expect(result.data['explanation_type']).to eq('transaction')
    end

    it 'works with pre-fetched payment_intent hash' do
      result = described_class.new.execute(
        context: {
          merchant_id: merchant.id,
          payment_intent: { id: 1, amount_cents: 2500, currency: 'USD', status: 'authorized', dispute_status: 'none' }
        }
      )
      expect(result.success).to be true
      expect(result.explanation).to include('authorized')
    end

    it 'includes audit metadata' do
      pi = merchant.payment_intents.create!(customer: customer, amount_cents: 1000, currency: 'USD', status: 'created')
      result = described_class.new.execute(context: { merchant_id: merchant.id, payment_intent_id: pi.id, agent_key: 'support_faq' })
      expect(result.metadata['merchant_id']).to eq(merchant.id.to_s)
      expect(result.metadata['agent_key']).to eq('support_faq')
    end
  end
end
