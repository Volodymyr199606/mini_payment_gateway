# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Tools::IntentDetector do
  describe '.detect' do
    it 'detects get_merchant_account' do
      expect(described_class.detect('my account info')).to eq(
        { tool_name: 'get_merchant_account', args: {} }
      )
      expect(described_class.detect('merchant summary')).to eq(
        { tool_name: 'get_merchant_account', args: {} }
      )
    end

    it 'detects get_payment_intent' do
      out = described_class.detect('payment intent 42')
      expect(out[:tool_name]).to eq('get_payment_intent')
      expect(out[:args][:payment_intent_id]).to eq(42)
    end

    it 'detects get_transaction by id' do
      out = described_class.detect('transaction 10')
      expect(out[:tool_name]).to eq('get_transaction')
      expect(out[:args][:transaction_id]).to eq(10)
    end

    it 'detects get_transaction by processor_ref' do
      out = described_class.detect('transaction txn_abc123')
      expect(out[:tool_name]).to eq('get_transaction')
      expect(out[:args][:processor_ref]).to eq('txn_abc123')
    end

    it 'detects get_ledger_summary for reporting phrases' do
      out = described_class.detect('how much last 7 days')
      expect(out[:tool_name]).to eq('get_ledger_summary')
      expect(out[:args]).to have_key(:from)
      expect(out[:args]).to have_key(:to)
    end

    it 'returns nil for non-matching message' do
      expect(described_class.detect('Hello')).to be_nil
      expect(described_class.detect('')).to be_nil
    end
  end
end
