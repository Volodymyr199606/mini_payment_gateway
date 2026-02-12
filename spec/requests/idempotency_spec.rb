# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Idempotency API', type: :request do
  before do
    stub_processor_success
    stub_webhook_delivery
  end

  def create_merchant_with_api_key
    Merchant.create_with_api_key(name: "Merchant #{SecureRandom.hex(4)}", status: 'active')
  end

  # 8. Authorize idempotency: same key → same response, only 1 auth transaction + ledger entries
  it 'authorize idempotency: same key returns same response, only 1 auth transaction and ledger entries' do
    m, key = create_merchant_with_api_key
    cust = Customer.create!(merchant: m, email: "cust_#{SecureRandom.hex(4)}@example.com")
    pm = PaymentMethod.create!(customer: cust, method_type: 'card', last4: '4242', brand: 'Visa', exp_month: 12, exp_year: 2026)
    pi = PaymentIntent.create!(merchant: m, customer: cust, payment_method: pm, amount_cents: 5000, currency: 'USD', status: 'created')

    idempotency_key = 'auth-ip-key-001'

    post "/api/v1/payment_intents/#{pi.id}/authorize",
         params: { idempotency_key: idempotency_key },
         headers: api_headers(key),
         as: :json
    expect(response).to have_http_status(:ok)
    first_body = response.parsed_body

    post "/api/v1/payment_intents/#{pi.id}/authorize",
         params: { idempotency_key: idempotency_key },
         headers: api_headers(key),
         as: :json
    expect(response).to have_http_status(:ok)
    second_body = response.parsed_body

    expect(second_body).to eq(first_body)
    expect(pi.reload.transactions.where(kind: 'authorize', status: 'succeeded').count).to eq(1)
    expect(pi.merchant.ledger_entries.where(entry_type: 'charge').count).to eq(1)
  end

  # 9. Capture idempotency: same key → only 1 capture transaction + ledger entries
  it 'capture idempotency: same key returns same response, only 1 capture transaction and ledger entries' do
    m, key = create_merchant_with_api_key
    cust = Customer.create!(merchant: m, email: "cust_#{SecureRandom.hex(4)}@example.com")
    pm = PaymentMethod.create!(customer: cust, method_type: 'card', last4: '4242', brand: 'Visa', exp_month: 12, exp_year: 2026)
    pi = PaymentIntent.create!(merchant: m, customer: cust, payment_method: pm, amount_cents: 5000, currency: 'USD', status: 'authorized')
    Transaction.create!(payment_intent: pi, kind: 'authorize', status: 'succeeded', amount_cents: 5000)

    idempotency_key = 'capture-ip-key-001'

    post "/api/v1/payment_intents/#{pi.id}/capture",
         params: { idempotency_key: idempotency_key },
         headers: api_headers(key),
         as: :json
    expect(response).to have_http_status(:ok)
    first_body = response.parsed_body

    post "/api/v1/payment_intents/#{pi.id}/capture",
         params: { idempotency_key: idempotency_key },
         headers: api_headers(key),
         as: :json
    expect(response).to have_http_status(:ok)
    second_body = response.parsed_body

    expect(second_body).to eq(first_body)
    expect(pi.reload.transactions.where(kind: 'capture', status: 'succeeded').count).to eq(1)
  end

  # 10. Refund idempotency: same key → only 1 refund transaction + ledger entries
  it 'refund idempotency: same key returns same response, only 1 refund transaction and ledger entries' do
    m, key = create_merchant_with_api_key
    cust = Customer.create!(merchant: m, email: "cust_#{SecureRandom.hex(4)}@example.com")
    pm = PaymentMethod.create!(customer: cust, method_type: 'card', last4: '4242', brand: 'Visa', exp_month: 12, exp_year: 2026)
    pi = PaymentIntent.create!(merchant: m, customer: cust, payment_method: pm, amount_cents: 5000, currency: 'USD', status: 'captured')
    Transaction.create!(payment_intent: pi, kind: 'authorize', status: 'succeeded', amount_cents: 5000)
    Transaction.create!(payment_intent: pi, kind: 'capture', status: 'succeeded', amount_cents: 5000)

    idempotency_key = 'refund-ip-key-001'

    post "/api/v1/payment_intents/#{pi.id}/refunds",
         params: { refund: { amount_cents: 2000 }, idempotency_key: idempotency_key },
         headers: api_headers(key),
         as: :json
    expect(response).to have_http_status(:created)
    first_body = response.parsed_body

    post "/api/v1/payment_intents/#{pi.id}/refunds",
         params: { refund: { amount_cents: 2000 }, idempotency_key: idempotency_key },
         headers: api_headers(key),
         as: :json
    expect(response).to have_http_status(:created)
    second_body = response.parsed_body

    expect(second_body).to eq(first_body)
    expect(pi.reload.transactions.where(kind: 'refund', status: 'succeeded').count).to eq(1)
  end
end
