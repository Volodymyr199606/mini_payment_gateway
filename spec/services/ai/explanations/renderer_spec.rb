# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Explanations::Renderer do
  describe '.render' do
    it 'returns nil for unknown tool' do
      expect(described_class.render('unknown_tool', { id: 1 })).to be_nil
    end

    it 'returns RenderedExplanation for payment_intent created' do
      data = { id: 42, amount_cents: 1000, currency: 'USD', status: 'created' }
      out = described_class.render('get_payment_intent', data)
      expect(out).to be_a(Ai::Explanations::RenderedExplanation)
      expect(out.deterministic).to be true
      expect(out.explanation_type).to eq('payment_intent')
      expect(out.explanation_key).to eq('created')
      expect(out.explanation_text).to include('42')
      expect(out.explanation_text).to include('$10.00')
      expect(out.explanation_text).to include('created')
    end

    it 'returns RenderedExplanation for transaction authorize succeeded' do
      data = { id: 1, kind: 'authorize', status: 'succeeded', amount_cents: 5000, processor_ref: 'ref_123' }
      out = described_class.render('get_transaction', data)
      expect(out).to be_a(Ai::Explanations::RenderedExplanation)
      expect(out.explanation_text).to include('succeeded')
      expect(out.explanation_text).to include('ref_123')
    end

    it 'returns RenderedExplanation for webhook delivery pending' do
      data = { id: 10, event_type: 'payment_intent.captured', delivery_status: 'pending', attempts: 0 }
      out = described_class.render('get_webhook_event', data)
      expect(out).to be_a(Ai::Explanations::RenderedExplanation)
      expect(out.explanation_text).to include('pending')
    end

    it 'returns RenderedExplanation for ledger summary' do
      data = {
        from: '2025-01-01',
        to: '2025-01-31',
        currency: 'USD',
        totals: { charges_cents: 10000, refunds_cents: 2000, fees_cents: 100, net_cents: 7900 },
        counts: { captures_count: 5, refunds_count: 1 }
      }
      out = described_class.render('get_ledger_summary', data)
      expect(out).to be_a(Ai::Explanations::RenderedExplanation)
      expect(out.explanation_text).to include('Charges')
      expect(out.explanation_text).to include('Net')
      expect(out.explanation_text).to include('6')
      expect(out.explanation_text).to include('charge/refund movements')
    end

    it 'returns RenderedExplanation for merchant account' do
      data = { id: 1, name: 'Test Merchant', status: 'active', payment_intents_count: 10, webhook_events_count: 5 }
      out = described_class.render('get_merchant_account', data)
      expect(out).to be_a(Ai::Explanations::RenderedExplanation)
      expect(out.explanation_text).to include('Test Merchant')
      expect(out.explanation_text).to include('active')
    end

    it 'to_audit_metadata returns safe hash' do
      data = { id: 1, status: 'authorized', amount_cents: 1000, currency: 'USD' }
      out = described_class.render('get_payment_intent', data)
      meta = out.to_audit_metadata
      expect(meta[:deterministic_explanation_used]).to be true
      expect(meta[:explanation_type]).to eq('payment_intent')
      expect(meta[:explanation_key]).to eq('authorized')
      expect(meta[:llm_skipped_due_to_template]).to be true
    end
  end
end
