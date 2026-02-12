# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Payment flow API', type: :request do
  before do
    stub_processor_success
    stub_webhook_delivery
  end

  def create_merchant_with_api_key
    Merchant.create_with_api_key(name: "Merchant #{SecureRandom.hex(4)}", status: 'active')
  end

  # 1. E2E happy path: create intent → authorize → capture → partial refund → full refund
  it 'completes full flow: create → authorize → capture → partial refund → full refund with correct amounts' do
    m, key = create_merchant_with_api_key
    cust = Customer.create!(merchant: m, email: "cust_#{SecureRandom.hex(4)}@example.com")
    pm = PaymentMethod.create!(customer: cust, method_type: 'card', last4: '4242', brand: 'Visa', exp_month: 12, exp_year: 2026)

    # Create intent (amount 10_000 cents = $100)
    post '/api/v1/payment_intents',
         params: { payment_intent: { customer_id: cust.id, payment_method_id: pm.id, amount_cents: 10_000, currency: 'USD' } },
         headers: api_headers(key),
         as: :json
    expect(response).to have_http_status(:created)
    pi = response.parsed_body['data']
    expect(pi['status']).to eq('created')

    # Authorize
    post "/api/v1/payment_intents/#{pi['id']}/authorize", params: { idempotency_key: 'e2e-auth-001' }, headers: api_headers(key), as: :json
    expect(response).to have_http_status(:ok)
    pi = response.parsed_body['data']['payment_intent']
    expect(pi['status']).to eq('authorized')

    # Capture
    post "/api/v1/payment_intents/#{pi['id']}/capture", params: { idempotency_key: 'e2e-cap-001' }, headers: api_headers(key), as: :json
    expect(response).to have_http_status(:ok)
    pi = response.parsed_body['data']['payment_intent']
    expect(pi['status']).to eq('captured')
    expect(pi['refundable_cents']).to eq(10_000)

    # Partial refund (3000 cents)
    post "/api/v1/payment_intents/#{pi['id']}/refunds",
         params: { refund: { amount_cents: 3000 } },
         headers: api_headers(key),
         as: :json
    expect(response).to have_http_status(:created)
    pi = response.parsed_body['data']['payment_intent']
    expect(pi['total_refunded_cents']).to eq(3000)
    expect(pi['refundable_cents']).to eq(7000)

    # Full refund (remaining 7000)
    post "/api/v1/payment_intents/#{pi['id']}/refunds", params: {}, headers: api_headers(key), as: :json
    expect(response).to have_http_status(:created)
    pi = response.parsed_body['data']['payment_intent']
    expect(pi['total_refunded_cents']).to eq(10_000)
    expect(pi['refundable_cents']).to eq(0)
    expect(pi['status']).to eq('captured')
  end

  # 2. Capture before authorize is rejected
  it 'rejects capture before authorize (422)' do
    m, key = create_merchant_with_api_key
    cust = Customer.create!(merchant: m, email: "cust_#{SecureRandom.hex(4)}@example.com")
    pm = PaymentMethod.create!(customer: cust, method_type: 'card', last4: '4242', brand: 'Visa', exp_month: 12, exp_year: 2026)
    pi = PaymentIntent.create!(merchant: m, customer: cust, payment_method: pm, amount_cents: 5000, currency: 'USD', status: 'created')

    post "/api/v1/payment_intents/#{pi.id}/capture", params: { idempotency_key: 'capture-before-auth' }, headers: api_headers(key), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']['code']).to eq('capture_failed')
  end

  # 3. Refund before capture is rejected
  it 'rejects refund before capture (422)' do
    m, key = create_merchant_with_api_key
    cust = Customer.create!(merchant: m, email: "cust_#{SecureRandom.hex(4)}@example.com")
    pm = PaymentMethod.create!(customer: cust, method_type: 'card', last4: '4242', brand: 'Visa', exp_month: 12, exp_year: 2026)
    pi = PaymentIntent.create!(merchant: m, customer: cust, payment_method: pm, amount_cents: 5000, currency: 'USD', status: 'authorized')
    Transaction.create!(payment_intent: pi, kind: 'authorize', status: 'succeeded', amount_cents: 5000)

    post "/api/v1/payment_intents/#{pi.id}/refunds",
         params: { refund: { amount_cents: 1000 } },
         headers: api_headers(key),
         as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']['code']).to eq('invalid_state')
  end

  # 4. Cannot capture twice (no second transaction)
  it 'rejects second capture (only one capture transaction)' do
    m, key = create_merchant_with_api_key
    cust = Customer.create!(merchant: m, email: "cust_#{SecureRandom.hex(4)}@example.com")
    pm = PaymentMethod.create!(customer: cust, method_type: 'card', last4: '4242', brand: 'Visa', exp_month: 12, exp_year: 2026)
    pi = PaymentIntent.create!(merchant: m, customer: cust, payment_method: pm, amount_cents: 5000, currency: 'USD', status: 'authorized')
    Transaction.create!(payment_intent: pi, kind: 'authorize', status: 'succeeded', amount_cents: 5000)

    post "/api/v1/payment_intents/#{pi.id}/capture", params: { idempotency_key: 'double-cap-001' }, headers: api_headers(key), as: :json
    expect(response).to have_http_status(:ok)

    post "/api/v1/payment_intents/#{pi.id}/capture", params: { idempotency_key: 'double-cap-001' }, headers: api_headers(key), as: :json
    # Same idempotency key returns cached 200; different key would return 422
    expect(response).to have_http_status(:ok)

    expect(pi.reload.transactions.where(kind: 'capture', status: 'succeeded').count).to eq(1)
  end

  # 5. Partial refund updates refundable amount correctly
  it 'partial refund updates refundable amount correctly' do
    m, key = create_merchant_with_api_key
    cust = Customer.create!(merchant: m, email: "cust_#{SecureRandom.hex(4)}@example.com")
    pm = PaymentMethod.create!(customer: cust, method_type: 'card', last4: '4242', brand: 'Visa', exp_month: 12, exp_year: 2026)
    pi = PaymentIntent.create!(merchant: m, customer: cust, payment_method: pm, amount_cents: 5000, currency: 'USD', status: 'captured')
    Transaction.create!(payment_intent: pi, kind: 'authorize', status: 'succeeded', amount_cents: 5000)
    Transaction.create!(payment_intent: pi, kind: 'capture', status: 'succeeded', amount_cents: 5000)

    post "/api/v1/payment_intents/#{pi.id}/refunds",
         params: { refund: { amount_cents: 2000 } },
         headers: api_headers(key),
         as: :json
    expect(response).to have_http_status(:created)
    pi.reload
    expect(pi.refundable_cents).to eq(3000)
    expect(pi.total_refunded_cents).to eq(2000)
  end

  # 6. Refund > captured is rejected
  it 'rejects refund exceeding captured amount' do
    m, key = create_merchant_with_api_key
    cust = Customer.create!(merchant: m, email: "cust_#{SecureRandom.hex(4)}@example.com")
    pm = PaymentMethod.create!(customer: cust, method_type: 'card', last4: '4242', brand: 'Visa', exp_month: 12, exp_year: 2026)
    pi = PaymentIntent.create!(merchant: m, customer: cust, payment_method: pm, amount_cents: 5000, currency: 'USD', status: 'captured')
    Transaction.create!(payment_intent: pi, kind: 'authorize', status: 'succeeded', amount_cents: 5000)
    Transaction.create!(payment_intent: pi, kind: 'capture', status: 'succeeded', amount_cents: 5000)

    post "/api/v1/payment_intents/#{pi.id}/refunds",
         params: { refund: { amount_cents: 6000 } },
         headers: api_headers(key),
         as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']['code']).to eq('validation_error')
  end

  # 7. Full refund sets refundable=0 (state stays captured)
  it 'full refund sets refundable_cents to 0 and status stays captured' do
    m, key = create_merchant_with_api_key
    cust = Customer.create!(merchant: m, email: "cust_#{SecureRandom.hex(4)}@example.com")
    pm = PaymentMethod.create!(customer: cust, method_type: 'card', last4: '4242', brand: 'Visa', exp_month: 12, exp_year: 2026)
    pi = PaymentIntent.create!(merchant: m, customer: cust, payment_method: pm, amount_cents: 5000, currency: 'USD', status: 'captured')
    Transaction.create!(payment_intent: pi, kind: 'authorize', status: 'succeeded', amount_cents: 5000)
    Transaction.create!(payment_intent: pi, kind: 'capture', status: 'succeeded', amount_cents: 5000)

    post "/api/v1/payment_intents/#{pi.id}/refunds", params: {}, headers: api_headers(key), as: :json
    expect(response).to have_http_status(:created)
    pi.reload
    expect(pi.refundable_cents).to eq(0)
    expect(pi.total_refunded_cents).to eq(5000)
    expect(pi.status).to eq('captured')
  end
end
