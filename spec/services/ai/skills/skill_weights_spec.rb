# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Skills::SkillWeights do
  describe '.weight' do
    it 'classifies payment_state_explainer as light' do
      expect(described_class.weight(:payment_state_explainer)).to eq(:light)
    end

    it 'classifies discrepancy_detector as heavy' do
      expect(described_class.weight(:discrepancy_detector)).to eq(:heavy)
    end

    it 'classifies reporting_trend_summary as heavy' do
      expect(described_class.weight(:reporting_trend_summary)).to eq(:heavy)
    end

    it 'classifies ledger_period_summary as medium' do
      expect(described_class.weight(:ledger_period_summary)).to eq(:medium)
    end
  end

  describe '.heavy_skills_count' do
    it 'counts heavy skills in array' do
      expect(described_class.heavy_skills_count(%i[payment_state_explainer discrepancy_detector reporting_trend_summary])).to eq(2)
    end
  end
end
