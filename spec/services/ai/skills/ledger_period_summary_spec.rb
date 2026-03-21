# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Skills::LedgerPeriodSummary do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }

  describe '#execute' do
    it 'returns failure when merchant_id missing' do
      result = described_class.new.execute(context: { preset: 'last_7_days' })
      expect(result.failure?).to be true
      expect(result.error_code).to eq('missing_context')
    end

    it 'returns failure when no range provided' do
      result = described_class.new.execute(context: { merchant_id: merchant.id })
      expect(result.failure?).to be true
      expect(result.error_code).to eq('missing_range')
    end

    it 'returns summary for preset last_7_days' do
      result = described_class.new.execute(context: { merchant_id: merchant.id, preset: 'last_7_days' })
      expect(result.success).to be true
      expect(result.explanation).to include('Ledger').or include('Charges').or include('Net')
      expect(result.data['totals']).to be_present
      expect(result.data['totals']).to have_key('charges_cents')
      expect(result.deterministic).to be true
    end

    it 'returns summary for preset all_time' do
      result = described_class.new.execute(context: { merchant_id: merchant.id, preset: 'all_time' })
      expect(result.success).to be true
      expect(result.data['summary_text']).to be_present
    end

    it 'parses time range from message' do
      result = described_class.new.execute(context: { merchant_id: merchant.id, message: 'summary for last 7 days' })
      expect(result.success).to be true
    end

    it 'includes audit metadata' do
      result = described_class.new.execute(context: { merchant_id: merchant.id, preset: 'yesterday', agent_key: 'reporting_calculation' })
      expect(result.metadata['merchant_id']).to eq(merchant.id.to_s)
      expect(result.metadata['explanation_type']).to eq('ledger_summary')
    end
  end
end
