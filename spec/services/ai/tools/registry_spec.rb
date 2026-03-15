# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Tools::Registry do
  describe '.resolve' do
    it 'resolves known tools' do
      expect(described_class.resolve('get_ledger_summary')).to eq(Ai::Tools::GetLedgerSummary)
      expect(described_class.resolve('get_payment_intent')).to eq(Ai::Tools::GetPaymentIntent)
      expect(described_class.resolve('get_transaction')).to eq(Ai::Tools::GetTransaction)
      expect(described_class.resolve('get_webhook_event')).to eq(Ai::Tools::GetWebhookEvent)
      expect(described_class.resolve('get_merchant_account')).to eq(Ai::Tools::GetMerchantAccount)
    end

    it 'returns nil for unknown tools' do
      expect(described_class.resolve('unknown_tool')).to be_nil
      expect(described_class.resolve('')).to be_nil
    end

    it 'is case insensitive' do
      expect(described_class.resolve('GET_LEDGER_SUMMARY')).to eq(Ai::Tools::GetLedgerSummary)
    end
  end

  describe '.known_tools' do
    it 'returns all tool names' do
      expect(described_class.known_tools).to contain_exactly(
        'get_ledger_summary',
        'get_payment_intent',
        'get_transaction',
        'get_webhook_event',
        'get_merchant_account'
      )
    end
  end

  describe '.definition' do
    it 'returns ToolDefinition for known tool' do
      d = described_class.definition('get_ledger_summary')
      expect(d).to be_a(Ai::Tools::ToolDefinition)
      expect(d.key).to eq('get_ledger_summary')
      expect(d.read_only?).to be true
      expect(d.cacheable?).to be true
    end

    it 'returns definition with cacheable false for get_payment_intent' do
      d = described_class.definition('get_payment_intent')
      expect(d.cacheable?).to be false
    end

    it 'returns nil for unknown tool' do
      expect(described_class.definition('unknown_tool')).to be_nil
    end
  end

  describe '.definitions' do
    it 'returns one definition per registered tool' do
      expect(described_class.definitions.size).to eq(described_class.known_tools.size)
    end
  end

  describe '.validate!' do
    it 'does not raise with current tools and definitions' do
      expect { described_class.validate! }.not_to raise_error
      expect(described_class.validate!).to be true
    end
  end
end
