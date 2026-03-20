# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IdempotencyFingerprint do
  let(:merchant_id) { 42 }

  describe '.compute' do
    it 'is stable for create_payment_intent regardless of metadata key order' do
      a = described_class.compute(
        merchant_id: merchant_id,
        endpoint: 'create_payment_intent',
        request_params: {
          customer_id: 1,
          amount_cents: 100,
          currency: 'usd',
          metadata: { 'z' => 1, 'a' => 2 },
          idempotency_key: 'idem-1'
        }
      )
      b = described_class.compute(
        merchant_id: merchant_id,
        endpoint: 'create_payment_intent',
        request_params: {
          amount_cents: 100,
          currency: 'USD',
          metadata: { 'a' => 2, 'z' => 1 },
          customer_id: 1,
          idempotency_key: 'idem-1'
        }
      )
      expect(a).to eq(b)
    end

    it 'excludes idempotency_key from logical payload so key string does not affect fingerprint' do
      a = described_class.compute(
        merchant_id: merchant_id,
        endpoint: 'create_payment_intent',
        request_params: { amount_cents: 50, currency: 'usd', idempotency_key: 'a' }
      )
      b = described_class.compute(
        merchant_id: merchant_id,
        endpoint: 'create_payment_intent',
        request_params: { amount_cents: 50, currency: 'usd', idempotency_key: 'b' }
      )
      expect(a).to eq(b)
    end

    it 'differs when mutation payload differs (refund amount)' do
      base = { payment_intent_id: 9, amount_cents: 1000 }
      other = { payment_intent_id: 9, amount_cents: 2000 }
      expect(
        described_class.compute(merchant_id: merchant_id, endpoint: 'refund', request_params: base)
      ).not_to eq(
        described_class.compute(merchant_id: merchant_id, endpoint: 'refund', request_params: other)
      )
    end

    it 'includes merchant and endpoint in envelope so scope is explicit in the hash' do
      same_payload = { payment_intent_id: 1 }
      auth = described_class.compute(merchant_id: 1, endpoint: 'authorize', request_params: same_payload)
      cap = described_class.compute(merchant_id: 1, endpoint: 'capture', request_params: same_payload)
      expect(auth).not_to eq(cap)

      m1 = described_class.compute(merchant_id: 1, endpoint: 'authorize', request_params: same_payload)
      m2 = described_class.compute(merchant_id: 2, endpoint: 'authorize', request_params: same_payload)
      expect(m1).not_to eq(m2)
    end
  end
end
