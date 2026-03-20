# frozen_string_literal: true

# Idempotency invariants: domain-level duplicate prevention + API replay correctness.
# Ties to hardened IdempotencyService semantics.
require 'rails_helper'

RSpec.describe 'Payment invariants: idempotency', :invariants, type: :request do
  include ApiHelpers

  before do
    stub_successful_provider
    stub_webhook_delivery
  end

  it 'CaptureService refuses second capture (domain-level duplicate prevention)' do
    pi = build_payment_intent(merchant: build_merchant, status: 'authorized')
    CaptureService.call(payment_intent: pi)

    second = CaptureService.call(payment_intent: pi.reload)

    expect(second).not_to be_success
    expect(pi.transactions.where(kind: 'capture', status: 'succeeded').count).to eq(1)
    expect(pi.merchant.ledger_entries.charges.count).to eq(1)
  end

  it 'identical authorize replay via API returns same result without duplicate transaction' do
    m, key = create_merchant_with_api_key
    pi = build_payment_intent(merchant: m, status: 'created')
    idem = 'inv-auth-replay'

    post "/api/v1/payment_intents/#{pi.id}/authorize",
         params: { idempotency_key: idem },
         headers: api_headers(key),
         as: :json
    expect(response).to have_http_status(:ok)
    first = response.parsed_body

    post "/api/v1/payment_intents/#{pi.id}/authorize",
         params: { idempotency_key: idem },
         headers: api_headers(key),
         as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(first)
    expect(pi.reload.transactions.where(kind: 'authorize', status: 'succeeded').count).to eq(1)
  end

  it 'identical capture replay via API does not duplicate ledger charge' do
    m, key = create_merchant_with_api_key
    pi = build_payment_intent(merchant: m, status: 'authorized')
    idem = 'inv-cap-replay'

    post "/api/v1/payment_intents/#{pi.id}/capture",
         params: { idempotency_key: idem },
         headers: api_headers(key),
         as: :json
    expect(response).to have_http_status(:ok)

    post "/api/v1/payment_intents/#{pi.id}/capture",
         params: { idempotency_key: idem },
         headers: api_headers(key),
         as: :json
    expect(response).to have_http_status(:ok)

    expect(pi.reload.merchant.ledger_entries.charges.count).to eq(1),
      'Idempotent capture replay must not create duplicate charge ledger entry'
  end

  it 'identical refund replay via API does not duplicate refund transaction or ledger' do
    m, key = create_merchant_with_api_key
    pi = build_payment_intent(merchant: m, status: 'captured')
    idem = 'inv-refund-replay'

    post "/api/v1/payment_intents/#{pi.id}/refunds",
         params: { refund: { amount_cents: 1000 }, idempotency_key: idem },
         headers: api_headers(key),
         as: :json
    expect(response).to have_http_status(:created)

    post "/api/v1/payment_intents/#{pi.id}/refunds",
         params: { refund: { amount_cents: 1000 }, idempotency_key: idem },
         headers: api_headers(key),
         as: :json
    expect(response).to have_http_status(:created)

    expect(pi.reload.transactions.where(kind: 'refund', status: 'succeeded').count).to eq(1)
    expect(pi.merchant.ledger_entries.refunds.count).to eq(1)
  end
end
