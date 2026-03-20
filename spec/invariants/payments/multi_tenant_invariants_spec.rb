# frozen_string_literal: true

# Multi-tenant invariants: one merchant cannot affect another's payment or financial records.
require 'rails_helper'

RSpec.describe 'Payment invariants: multi-tenant isolation', :invariants, type: :request do
  include ApiHelpers

  before do
    stub_successful_provider
    stub_webhook_delivery
  end

  it 'merchant A cannot capture merchant B payment intent via API' do
    m_a, key_a = create_merchant_with_api_key(name: 'A', email: "a_#{SecureRandom.hex(4)}@example.com")
    m_b, key_b = create_merchant_with_api_key(name: 'B', email: "b_#{SecureRandom.hex(4)}@example.com")

    pi_b = build_payment_intent(merchant: m_b, status: 'authorized')

    post "/api/v1/payment_intents/#{pi_b.id}/capture",
         params: { idempotency_key: 'cross-tenant' },
         headers: api_headers(key_a),
         as: :json

    expect(response).to have_http_status(:not_found)
    expect(pi_b.reload.status).to eq('authorized')
    expect(m_b.ledger_entries.count).to eq(0)
  end

  it 'ledger entries are scoped to merchant' do
    m_a = build_merchant
    m_b = build_merchant

    pi_a = build_payment_intent(merchant: m_a, status: 'authorized', amount_cents: 5000)
    pi_b = build_payment_intent(merchant: m_b, status: 'authorized', amount_cents: 3000)

    CaptureService.call(payment_intent: pi_a)
    CaptureService.call(payment_intent: pi_b)

    expect(m_a.reload.ledger_entries.charges.sum(:amount_cents)).to eq(5000)
    expect(m_b.reload.ledger_entries.charges.sum(:amount_cents)).to eq(3000)
    expect(m_a.ledger_entries.pluck(:merchant_id).uniq).to eq([m_a.id])
    expect(m_b.ledger_entries.pluck(:merchant_id).uniq).to eq([m_b.id])
  end
end
