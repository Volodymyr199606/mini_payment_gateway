# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IdempotencyService do
  let(:merchant) do
    Merchant.create_with_api_key(
      name: 'T',
      email: "m_#{SecureRandom.hex(4)}@example.com",
      password: 'password123',
      password_confirmation: 'password123',
      status: 'active'
    ).first
  end

  describe '#call' do
    it 'returns cached result when canonical fingerprint matches' do
      key = 'idem-canonical'
      body = { 'data' => { 'ok' => true } }
      fp = IdempotencyFingerprint.compute(
        merchant_id: merchant.id,
        endpoint: 'authorize',
        request_params: { payment_intent_id: 7 }
      )
      IdempotencyRecord.create!(
        merchant: merchant,
        idempotency_key: key,
        endpoint: 'authorize',
        request_hash: fp,
        response_body: body,
        status_code: 200
      )

      svc = described_class.call(
        merchant: merchant,
        idempotency_key: key,
        endpoint: 'authorize',
        request_params: { payment_intent_id: 7 }
      )

      expect(svc.result[:cached]).to be true
      expect(svc.result[:response_body]).to eq(body)
    end

    it 'returns cached result for legacy-stored request_hash (pre-hardening rows)' do
      key = 'idem-legacy'
      body = { 'legacy' => true }
      params = { payment_intent_id: 99 }
      legacy = IdempotencyFingerprint.legacy_compute(params)
      IdempotencyRecord.create!(
        merchant: merchant,
        idempotency_key: key,
        endpoint: 'authorize',
        request_hash: legacy,
        response_body: body,
        status_code: 200
      )

      svc = described_class.call(
        merchant: merchant,
        idempotency_key: key,
        endpoint: 'authorize',
        request_params: params
      )

      expect(svc.result[:cached]).to be true
      expect(svc.result[:response_body]).to eq(body)
    end

    it 'returns conflict when same key and endpoint but payload differs' do
      key = 'idem-conflict'
      params_first = { payment_intent_id: 1 }
      fp_first = IdempotencyFingerprint.compute(
        merchant_id: merchant.id,
        endpoint: 'authorize',
        request_params: params_first
      )
      IdempotencyRecord.create!(
        merchant: merchant,
        idempotency_key: key,
        endpoint: 'authorize',
        request_hash: fp_first,
        response_body: { ok: true },
        status_code: 200
      )

      svc = nil
      expect do
        svc = described_class.call(
          merchant: merchant,
          idempotency_key: key,
          endpoint: 'authorize',
          request_params: { payment_intent_id: 2 }
        )
      end.to change(AuditLog, :count).by(1)

      expect(svc.result[:conflict]).to be true
      expect(svc.result[:cached]).to be false
      expect(AuditLog.last.action).to eq('idempotency_mismatch')
    end

    it 'creates placeholder when no record exists' do
      svc = described_class.call(
        merchant: merchant,
        idempotency_key: 'new-key',
        endpoint: 'void',
        request_params: { payment_intent_id: 5 }
      )
      expect(svc.result[:cached]).to be false
      expect(svc.result[:idempotency_record]).to be_persisted
      expect(svc.result[:idempotency_record].response_body).to eq({ 'pending' => true })
    end

    it 'no-ops when idempotency_key is blank' do
      svc = described_class.call(
        merchant: merchant,
        idempotency_key: '',
        endpoint: 'authorize',
        request_params: { payment_intent_id: 1 }
      )
      expect(svc.result).to be_nil
    end
  end
end
