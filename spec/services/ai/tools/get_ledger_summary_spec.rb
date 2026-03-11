# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Tools::GetLedgerSummary do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }
  let(:context) { { 'merchant_id' => merchant.id } }

  describe '#call' do
    it 'returns structured error when merchant_id missing' do
      tool = described_class.new(args: { preset: 'all_time' }, context: {})
      result = tool.call
      expect(result[:success]).to be false
      expect(result[:error]).to include('merchant')
    end

    it 'returns error for missing range' do
      tool = described_class.new(args: {}, context: context)
      result = tool.call
      expect(result[:success]).to be false
      expect(result[:error]).to include('range')
    end

    it 'returns ledger summary for preset all_time' do
      tool = described_class.new(args: { preset: 'all_time' }, context: context)
      result = tool.call
      expect(result[:success]).to be true
      expect(result[:data]).to have_key(:totals)
      expect(result[:data][:totals]).to have_key(:charges_cents)
      expect(result[:data][:totals]).to have_key(:net_cents)
    end

    it 'remains deterministic' do
      tool = described_class.new(args: { preset: 'all_time' }, context: context)
      r1 = tool.call
      r2 = described_class.new(args: { preset: 'all_time' }, context: context).call
      expect(r1[:data][:totals]).to eq(r2[:data][:totals])
    end
  end
end
