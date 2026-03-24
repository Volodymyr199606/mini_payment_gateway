# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Skills::ReportingTrendSummary do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }

  before do
    allow(Reporting::LedgerSummary).to receive(:new).and_return(
      instance_double(
        Reporting::LedgerSummary,
        call: {
          currency: 'USD',
          from: '2025-01-01T00:00:00Z',
          to: '2025-01-08T00:00:00Z',
          totals: { charges_cents: 150_00, refunds_cents: 30_00, fees_cents: 5_00, net_cents: 115_00 }
        }
      )
    )
  end

  describe '#execute' do
    it 'produces trend summary when comparative data available' do
      prev_stub = instance_double(
        Reporting::LedgerSummary,
        call: {
          currency: 'USD',
          totals: { charges_cents: 100_00, refunds_cents: 20_00, fees_cents: 5_00, net_cents: 75_00 }
        }
      )
      call_count = 0
      allow(Reporting::LedgerSummary).to receive(:new) do |*_args|
        call_count += 1
        call_count == 1 ? prev_stub : instance_double(Reporting::LedgerSummary, call: {
          currency: 'USD', from: '2025-01-08', to: '2025-01-15',
          totals: { charges_cents: 150_00, refunds_cents: 30_00, fees_cents: 5_00, net_cents: 115_00 }
        })
      end

      context = { merchant_id: merchant.id, preset: 'last_7_days' }
      result = described_class.new.execute(context: context)

      expect(result.success).to be true
      expect(result.explanation).to include('Trend summary')
      expect(result.data['trend_available']).to be true
    end

    it 'returns no-comparison message when previous period unavailable' do
      context = {
        merchant_id: merchant.id,
        ledger_summary: {
          from: '2025-01-01T00:00:00Z',
          to: '2025-01-08T00:00:00Z',
          currency: 'USD',
          totals: { charges_cents: 100_00, refunds_cents: 0, fees_cents: 0, net_cents: 100_00 }
        }
      }
      allow(Reporting::LedgerSummary).to receive(:new).and_return(
        instance_double(Reporting::LedgerSummary, call: nil)
      )

      result = described_class.new.execute(context: context)

      expect(result.success).to be true
      expect(result.explanation).to include('No comparative period')
      expect(result.data['trend_available']).to eq(false)
    end

    it 'returns failure when no ledger data' do
      context = { merchant_id: merchant.id }
      allow(Reporting::LedgerSummary).to receive(:new).and_return(
        instance_double(Reporting::LedgerSummary, call: nil)
      )

      result = described_class.new.execute(context: context)

      expect(result.failure?).to be true
      expect(result.error_code).to eq('no_ledger_data')
    end

    it 'returns failure when merchant_id missing' do
      context = {}
      result = described_class.new.execute(context: context)

      expect(result.failure?).to be true
      expect(result.error_code).to eq('missing_context')
    end
  end
end
