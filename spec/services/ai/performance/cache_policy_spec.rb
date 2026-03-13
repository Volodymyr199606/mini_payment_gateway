# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Performance::CachePolicy do
  describe '.ttl_for' do
    it 'returns correct TTLs for each category' do
      expect(described_class.ttl_for(:retrieval)).to eq(120)
      expect(described_class.ttl_for(:ledger)).to eq(45)
      expect(described_class.ttl_for(:merchant_account)).to eq(60)
      expect(described_class.ttl_for(:memory)).to eq(30)
      expect(described_class.ttl_for(:tool_other)).to eq(30)
      expect(described_class.ttl_for(:unknown)).to eq(30)
    end
  end

  describe '.bypass?' do
    it 'returns true when ai_debug? is true' do
      allow(described_class).to receive(:ai_debug?).and_return(true)
      allow(described_class).to receive(:cache_bypass?).and_return(false)
      expect(described_class.bypass?).to be true
    end

    it 'returns true when cache_bypass? is true' do
      allow(described_class).to receive(:ai_debug?).and_return(false)
      allow(described_class).to receive(:cache_bypass?).and_return(true)
      expect(described_class.bypass?).to be true
    end

    it 'returns false when neither is set' do
      allow(described_class).to receive(:ai_debug?).and_return(false)
      allow(described_class).to receive(:cache_bypass?).and_return(false)
      expect(described_class.bypass?).to be false
    end
  end

  describe '.cacheable_tool?' do
    it 'returns true for get_merchant_account and get_ledger_summary' do
      expect(described_class.cacheable_tool?('get_merchant_account')).to be true
      expect(described_class.cacheable_tool?('get_ledger_summary')).to be true
    end

    it 'returns false for other tools' do
      expect(described_class.cacheable_tool?('get_payment_intent')).to be false
      expect(described_class.cacheable_tool?('unknown')).to be false
    end
  end

  describe '.tool_category' do
    it 'returns correct category per tool' do
      expect(described_class.tool_category('get_merchant_account')).to eq(:merchant_account)
      expect(described_class.tool_category('get_ledger_summary')).to eq(:ledger)
      expect(described_class.tool_category('get_payment_intent')).to eq(:tool_other)
    end
  end
end
