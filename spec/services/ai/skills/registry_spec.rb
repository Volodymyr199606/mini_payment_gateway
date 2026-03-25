# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Skills::Registry do
  describe '.fetch' do
    it 'returns skill class for known keys' do
      expect(described_class.fetch(:payment_state_explainer)).to eq(Ai::Skills::PaymentStateExplainer)
      expect(described_class.fetch(:ledger_period_summary)).to eq(Ai::Skills::LedgerPeriodSummary)
    end

    it 'raises UnknownSkillError for unknown keys' do
      expect { described_class.fetch(:unknown_skill) }.to raise_error(Ai::Skills::Registry::UnknownSkillError)
    end
  end

  describe '.known?' do
    it 'returns true for registered keys' do
      expect(described_class.known?(:payment_state_explainer)).to be(true)
    end

    it 'returns false for unknown keys' do
      expect(described_class.known?(:not_a_skill)).to be(false)
    end
  end

  describe '.all_keys' do
    it 'has unique keys' do
      keys = described_class.all_keys
      expect(keys.size).to eq(keys.uniq.size)
    end
  end

  describe '.definition' do
    it 'returns SkillDefinition with metadata' do
      d = described_class.definition(:payment_state_explainer)
      expect(d).to be_a(Ai::Skills::SkillDefinition)
      expect(d.key).to eq(:payment_state_explainer)
      expect(d.deterministic?).to be(true)
    end
  end

  describe '.validate!' do
    it 'does not raise' do
      expect { described_class.validate! }.not_to raise_error
      expect(described_class.validate!).to be true
    end
  end
end
