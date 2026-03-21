# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Skills::DiscrepancyDetector do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }
  let(:customer) { merchant.customers.create!(email: "cust_#{SecureRandom.hex(4)}@example.com") }

  describe '#execute' do
    it 'returns failure when merchant_id missing' do
      result = described_class.new.execute(context: {})
      expect(result.failure?).to be true
      expect(result.error_code).to eq('missing_context')
    end

    it 'returns aligned when ledger summary is consistent' do
      ledger = {
        totals: { charges_cents: 10000, refunds_cents: 2000, fees_cents: 100, net_cents: 7900 },
        counts: { captures_count: 5, refunds_count: 1 }
      }
      result = described_class.new.execute(
        context: { merchant_id: merchant.id, ledger_summary: ledger }
      )
      expect(result.success).to be true
      expect(result.data['aligned']).to be true
      expect(result.explanation).to include('aligned')
    end

    it 'detects refunds exceeding charges' do
      ledger = {
        totals: { charges_cents: 1000, refunds_cents: 2000, fees_cents: 0, net_cents: -1000 },
        counts: {}
      }
      result = described_class.new.execute(
        context: { merchant_id: merchant.id, ledger_summary: ledger }
      )
      expect(result.success).to be true
      expect(result.data['aligned']).to be false
      expect(result.data['discrepancies']).to include(match(/Refunds.*exceed/))
    end

    it 'fetches ledger when not provided and uses preset' do
      result = described_class.new.execute(
        context: { merchant_id: merchant.id, preset: 'last_7_days' }
      )
      expect(result.success).to be true
      expect(result.data['aligned']).to be true
    end

    it 'checks payment intents for capture/transaction consistency' do
      pi = merchant.payment_intents.create!(
        customer: customer,
        amount_cents: 5000,
        currency: 'USD',
        status: 'captured'
      )
      pi.transactions.create!(kind: 'capture', status: 'succeeded', amount_cents: 5000, processor_ref: 'cap_1')
      result = described_class.new.execute(
        context: { merchant_id: merchant.id, payment_intent_id: pi.id }
      )
      expect(result.success).to be true
      expect(result.data['aligned']).to be true
    end

    it 'detects captured intent without capture transaction' do
      pi = merchant.payment_intents.create!(
        customer: customer,
        amount_cents: 5000,
        currency: 'USD',
        status: 'captured'
      )
      result = described_class.new.execute(
        context: { merchant_id: merchant.id, payment_intent_id: pi.id }
      )
      expect(result.success).to be true
      expect(result.data['aligned']).to be false
      expect(result.data['discrepancies']).to include(match(/no successful capture transaction/))
    end

    it 'includes audit metadata' do
      result = described_class.new.execute(
        context: {
          merchant_id: merchant.id,
          ledger_summary: { totals: { charges_cents: 100, refunds_cents: 0, fees_cents: 0, net_cents: 100 }, counts: {} },
          agent_key: 'reconciliation_analyst'
        }
      )
      expect(result.metadata['merchant_id']).to eq(merchant.id.to_s)
      expect(result.metadata['aligned']).to be_present
    end
  end
end
