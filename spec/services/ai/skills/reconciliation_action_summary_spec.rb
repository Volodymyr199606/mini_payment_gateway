# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Skills::ReconciliationActionSummary do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }

  describe '#execute' do
    it 'produces next-step guidance when ledger present' do
      context = {
        merchant_id: merchant.id,
        ledger_summary: {
          totals: { charges_cents: 100_00, refunds_cents: 20_00, fees_cents: 5_00, net_cents: 75_00 }
        }
      }
      result = described_class.new.execute(context: context)

      expect(result.success).to be true
      expect(result.explanation).to include('**Suggested next steps (bounded):**')
      expect(result.explanation).to include('•')
      expect(result.data['actions']).to be_an(Array)
      expect(result.data['actions']).not_to be_empty
    end

    it 'suggests specific actions when refunds exceed charges' do
      context = {
        merchant_id: merchant.id,
        ledger_summary: {
          totals: { charges_cents: 50_00, refunds_cents: 100_00, fees_cents: 0, net_cents: -50_00 }
        }
      }
      result = described_class.new.execute(context: context)

      expect(result.success).to be true
      expect(result.explanation).to include('refund')
      expect(result.data['has_discrepancies']).to be true
    end

    it 'fetches ledger when preset provided' do
      ledger_result = {
        currency: 'USD',
        from: '2025-01-01',
        to: '2025-01-08',
        totals: { charges_cents: 100_00, refunds_cents: 10_00, fees_cents: 5_00, net_cents: 85_00 }
      }
      stub = instance_double(Reporting::LedgerSummary, call: ledger_result)
      allow(Reporting::LedgerSummary).to receive(:new).and_return(stub)

      context = { merchant_id: merchant.id, preset: 'last_7_days' }
      result = described_class.new.execute(context: context)

      expect(result.success).to be true
      expect(Reporting::LedgerSummary).to have_received(:new)
    end

    it 'returns failure when merchant_id missing' do
      context = {}
      result = described_class.new.execute(context: context)

      expect(result.failure?).to be true
      expect(result.error_code).to eq('missing_context')
    end
  end
end
