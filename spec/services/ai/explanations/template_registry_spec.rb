# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Explanations::TemplateRegistry do
  describe '.select_key' do
    context 'get_payment_intent' do
      it 'selects created for status created' do
        key = described_class.select_key('get_payment_intent', { status: 'created', id: 1 })
        expect(key).to eq('created')
      end

      it 'selects authorized for status authorized' do
        key = described_class.select_key('get_payment_intent', { status: 'authorized' })
        expect(key).to eq('authorized')
      end

      it 'selects disputed_open when dispute_status open' do
        key = described_class.select_key('get_payment_intent', { status: 'captured', dispute_status: 'open' })
        expect(key).to eq('disputed_open')
      end

      it 'selects refunded for status refunded' do
        key = described_class.select_key('get_payment_intent', { status: 'refunded' })
        expect(key).to eq('refunded')
      end
    end

    context 'get_transaction' do
      it 'selects authorize_succeeded for kind authorize and status succeeded' do
        key = described_class.select_key('get_transaction', { kind: 'authorize', status: 'succeeded' })
        expect(key).to eq('authorize_succeeded')
      end

      it 'selects transaction_failed for status failed' do
        key = described_class.select_key('get_transaction', { kind: 'capture', status: 'failed' })
        expect(key).to eq('transaction_failed')
      end
    end

    context 'get_webhook_event' do
      it 'selects delivery_pending for delivery_status pending' do
        key = described_class.select_key('get_webhook_event', { delivery_status: 'pending' })
        expect(key).to eq('delivery_pending')
      end
    end

    context 'get_ledger_summary' do
      it 'selects summary' do
        key = described_class.select_key('get_ledger_summary', { totals: {}, counts: {} })
        expect(key).to eq('summary')
      end
    end

    context 'get_merchant_account' do
      it 'selects account_summary' do
        key = described_class.select_key('get_merchant_account', { id: 1, name: 'Acme' })
        expect(key).to eq('account_summary')
      end
    end

    it 'returns nil for unknown tool' do
      expect(described_class.select_key('unknown_tool', {})).to be_nil
    end

    it 'returns nil for blank or nil data' do
      expect(described_class.select_key('get_payment_intent', nil)).to be_nil
      expect(described_class.select_key('get_payment_intent', {})).to be_nil
    end
  end
end
