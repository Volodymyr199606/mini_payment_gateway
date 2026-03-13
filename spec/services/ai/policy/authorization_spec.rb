# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Policy::Authorization do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }
  let(:other_merchant) { create_merchant_with_api_key(name: 'Other').first }
  let(:context) { { merchant_id: merchant.id } }

  describe '.call' do
    it 'returns an Authorization instance' do
      auth = described_class.call(context: context)
      expect(auth).to be_a(described_class)
      expect(auth.merchant_id).to eq(merchant.id)
    end
  end

  describe '#allow_tool?' do
    it 'denies when merchant_id is missing' do
      auth = described_class.call(context: {})
      d = auth.allow_tool?(tool_name: 'get_payment_intent', args: { payment_intent_id: 1 })
      expect(d.denied?).to be true
      expect(d.reason_code).to eq(Ai::Policy::Authorization::REASON_MERCHANT_REQUIRED)
    end

    it 'denies when merchant_id is nil' do
      auth = described_class.call(context: { merchant_id: nil })
      d = auth.allow_tool?(tool_name: 'get_payment_intent', args: {})
      expect(d.denied?).to be true
    end

    it 'allows known tool with merchant context' do
      auth = described_class.call(context: context)
      d = auth.allow_tool?(tool_name: 'get_payment_intent', args: { payment_intent_id: 1 })
      expect(d.allowed?).to be true
    end

    it 'denies unknown tool' do
      auth = described_class.call(context: context)
      d = auth.allow_tool?(tool_name: 'fetch_all_merchants_data', args: {})
      expect(d.denied?).to be true
      expect(d.reason_code).to eq(Ai::Policy::Authorization::REASON_TOOL_NOT_ALLOWED)
    end

    it 'allows get_ledger_summary when merchant_id present' do
      auth = described_class.call(context: context)
      d = auth.allow_tool?(tool_name: 'get_ledger_summary', args: { from: '2025-01-01', to: '2025-01-31' })
      expect(d.allowed?).to be true
    end
  end

  describe '#allow_record?' do
    it 'denies nil record' do
      auth = described_class.call(context: context)
      d = auth.allow_record?(record: nil, record_type: 'payment_intent')
      expect(d.denied?).to be true
      expect(d.reason_code).to eq(Ai::Policy::Authorization::REASON_RECORD_NOT_FOUND)
    end

    it 'denies when merchant_id missing' do
      pi = merchant.payment_intents.create!(
        customer_id: merchant.customers.create!(email: 'c@x.com', merchant_id: merchant.id).id,
        amount_cents: 1000,
        currency: 'USD'
      )
      auth = described_class.call(context: {})
      d = auth.allow_record?(record: pi, record_type: 'payment_intent')
      expect(d.denied?).to be true
      expect(d.reason_code).to eq(Ai::Policy::Authorization::REASON_MERCHANT_REQUIRED)
    end

    it 'denies record owned by another merchant' do
      pi = merchant.payment_intents.create!(
        customer_id: merchant.customers.create!(email: 'c@x.com', merchant_id: merchant.id).id,
        amount_cents: 1000,
        currency: 'USD'
      )
      auth = described_class.call(context: { merchant_id: other_merchant.id })
      d = auth.allow_record?(record: pi, record_type: 'payment_intent')
      expect(d.denied?).to be true
      expect(d.reason_code).to eq(Ai::Policy::Authorization::REASON_RECORD_NOT_OWNED)
    end

    it 'allows record owned by current merchant' do
      pi = merchant.payment_intents.create!(
        customer_id: merchant.customers.create!(email: 'c@x.com', merchant_id: merchant.id).id,
        amount_cents: 1000,
        currency: 'USD'
      )
      auth = described_class.call(context: context)
      d = auth.allow_record?(record: pi, record_type: 'payment_intent')
      expect(d.allowed?).to be true
    end

    it 'denies merchant record when id does not match context merchant' do
      auth = described_class.call(context: { merchant_id: merchant.id })
      d = auth.allow_record?(record: other_merchant, record_type: 'merchant')
      expect(d.denied?).to be true
      expect(d.reason_code).to eq(Ai::Policy::Authorization::REASON_RECORD_NOT_OWNED)
    end

    it 'allows merchant record when id matches context merchant' do
      auth = described_class.call(context: context)
      d = auth.allow_record?(record: merchant, record_type: 'merchant')
      expect(d.allowed?).to be true
    end
  end

  describe '#allow_entity_reference?' do
    it 'denies when merchant_id missing' do
      auth = described_class.call(context: {})
      d = auth.allow_entity_reference?(entity_type: 'payment_intent', entity_id: 1)
      expect(d.denied?).to be true
      expect(d.reason_code).to eq(Ai::Policy::Authorization::REASON_MERCHANT_REQUIRED)
    end

    it 'denies when entity_id blank' do
      auth = described_class.call(context: context)
      d = auth.allow_entity_reference?(entity_type: 'payment_intent', entity_id: nil)
      expect(d.denied?).to be true
      expect(d.reason_code).to eq(Ai::Policy::Authorization::REASON_ENTITY_INVALID)
    end

    it 'denies payment_intent owned by another merchant' do
      pi = merchant.payment_intents.create!(
        customer_id: merchant.customers.create!(email: 'c@x.com', merchant_id: merchant.id).id,
        amount_cents: 1000,
        currency: 'USD'
      )
      auth = described_class.call(context: { merchant_id: other_merchant.id })
      d = auth.allow_entity_reference?(entity_type: 'payment_intent', entity_id: pi.id)
      expect(d.denied?).to be true
      expect(d.reason_code).to eq(Ai::Policy::Authorization::REASON_RECORD_NOT_OWNED)
    end

    it 'allows payment_intent owned by current merchant' do
      pi = merchant.payment_intents.create!(
        customer_id: merchant.customers.create!(email: 'c@x.com', merchant_id: merchant.id).id,
        amount_cents: 1000,
        currency: 'USD'
      )
      auth = described_class.call(context: context)
      d = auth.allow_entity_reference?(entity_type: 'payment_intent', entity_id: pi.id)
      expect(d.allowed?).to be true
    end

    it 'denies transaction owned by another merchant' do
      pi = merchant.payment_intents.create!(
        customer_id: merchant.customers.create!(email: 'c@x.com', merchant_id: merchant.id).id,
        amount_cents: 1000,
        currency: 'USD'
      )
      tx = Transaction.create!(payment_intent: pi, processor_ref: "ref_#{SecureRandom.hex(8)}", amount_cents: 1000, kind: 'authorize', status: 'succeeded')
      auth = described_class.call(context: { merchant_id: other_merchant.id })
      d = auth.allow_entity_reference?(entity_type: 'transaction', entity_id: tx.id)
      expect(d.denied?).to be true
    end

    it 'allows transaction owned by current merchant via payment_intent' do
      pi = merchant.payment_intents.create!(
        customer_id: merchant.customers.create!(email: 'c@x.com', merchant_id: merchant.id).id,
        amount_cents: 1000,
        currency: 'USD'
      )
      tx = Transaction.create!(payment_intent: pi, processor_ref: "ref_#{SecureRandom.hex(8)}", amount_cents: 1000, kind: 'authorize', status: 'succeeded')
      auth = described_class.call(context: context)
      d = auth.allow_entity_reference?(entity_type: 'transaction', entity_id: tx.id)
      expect(d.allowed?).to be true
    end

    it 'denies webhook_event owned by another merchant' do
      we = WebhookEvent.create!(merchant: merchant, event_type: 'payment_intent.succeeded', payload: { id: 'ev_1' })
      auth = described_class.call(context: { merchant_id: other_merchant.id })
      d = auth.allow_entity_reference?(entity_type: 'webhook_event', entity_id: we.id)
      expect(d.denied?).to be true
    end

    it 'allows webhook_event owned by current merchant' do
      we = WebhookEvent.create!(merchant: merchant, event_type: 'payment_intent.succeeded', payload: { id: 'ev_1' })
      auth = described_class.call(context: context)
      d = auth.allow_entity_reference?(entity_type: 'webhook_event', entity_id: we.id)
      expect(d.allowed?).to be true
    end
  end

  describe '#allow_followup_inheritance?' do
    it 'delegates to allow_entity_reference and denies cross-merchant' do
      pi = merchant.payment_intents.create!(
        customer_id: merchant.customers.create!(email: 'c@x.com', merchant_id: merchant.id).id,
        amount_cents: 1000,
        currency: 'USD'
      )
      auth = described_class.call(context: { merchant_id: other_merchant.id })
      d = auth.allow_followup_inheritance?(entity_type: 'payment_intent', entity_id: pi.id)
      expect(d.denied?).to be true
    end

    it 'allows when entity owned by current merchant' do
      pi = merchant.payment_intents.create!(
        customer_id: merchant.customers.create!(email: 'c@x.com', merchant_id: merchant.id).id,
        amount_cents: 1000,
        currency: 'USD'
      )
      auth = described_class.call(context: context)
      d = auth.allow_followup_inheritance?(entity_type: 'payment_intent', entity_id: pi.id)
      expect(d.allowed?).to be true
    end
  end

  describe '.denied_message' do
    it 'returns generic safe message' do
      msg = described_class.denied_message
      expect(msg).to eq('Could not fetch data.')
      expect(msg).not_to include('merchant')
      expect(msg).not_to include('not found')
      expect(msg).not_to include('exist')
    end
  end
end
