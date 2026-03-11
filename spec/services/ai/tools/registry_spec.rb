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
end
