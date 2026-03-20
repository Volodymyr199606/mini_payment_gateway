# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Idempotency API', type: :request do
  before do
    stub_processor_success
    stub_webhook_delivery
  end

  # 8. Authorize idempotency: same key → same response, only 1 auth transaction (no ledger on authorize)
  it 'authorize idempotency: same key returns same response, only 1 auth transaction' do
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
    # Ledger entries are created on capture, not authorize
    expect(pi.merchant.ledger_entries.where(entry_type: 'charge').count).to eq(0)
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
    expect(pi.merchant.ledger_entries.where(entry_type: 'charge').count).to eq(1)
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

  it 'returns 409 when the same idempotency key is reused with a different authorize target' do
    m, key = create_merchant_with_api_key
    cust = Customer.create!(merchant: m, email: "cust_#{SecureRandom.hex(4)}@example.com")
    pm = PaymentMethod.create!(customer: cust, method_type: 'card', last4: '4242', brand: 'Visa', exp_month: 12, exp_year: 2026)
    pi1 = PaymentIntent.create!(merchant: m, customer: cust, payment_method: pm, amount_cents: 5000, currency: 'USD', status: 'created')
    pi2 = PaymentIntent.create!(merchant: m, customer: cust, payment_method: pm, amount_cents: 3000, currency: 'USD', status: 'created')

    idempotency_key = 'auth-cross-pi-key'

    post "/api/v1/payment_intents/#{pi1.id}/authorize",
         params: { idempotency_key: idempotency_key },
         headers: api_headers(key),
         as: :json
    expect(response).to have_http_status(:ok)

    post "/api/v1/payment_intents/#{pi2.id}/authorize",
         params: { idempotency_key: idempotency_key },
         headers: api_headers(key),
         as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.dig('error', 'code')).to eq('idempotency_conflict')
  end

  it 'returns 409 when the same idempotency key is reused for void on a different payment intent' do
    m, key = create_merchant_with_api_key
    cust = Customer.create!(merchant: m, email: "cust_#{SecureRandom.hex(4)}@example.com")
    pm = PaymentMethod.create!(customer: cust, method_type: 'card', last4: '4242', brand: 'Visa', exp_month: 12, exp_year: 2026)
    pi1 = PaymentIntent.create!(merchant: m, customer: cust, payment_method: pm, amount_cents: 5000, currency: 'USD', status: 'created')
    pi2 = PaymentIntent.create!(merchant: m, customer: cust, payment_method: pm, amount_cents: 4000, currency: 'USD', status: 'created')

    idempotency_key = 'void-cross-pi-key'

    post "/api/v1/payment_intents/#{pi1.id}/void",
         params: { idempotency_key: idempotency_key },
         headers: api_headers(key),
         as: :json
    expect(response).to have_http_status(:ok)

    post "/api/v1/payment_intents/#{pi2.id}/void",
         params: { idempotency_key: idempotency_key },
         headers: api_headers(key),
         as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.dig('error', 'code')).to eq('idempotency_conflict')
  end

  it 'returns 409 when the same idempotency key is reused for capture on a different payment intent' do
    m, key = create_merchant_with_api_key
    cust = Customer.create!(merchant: m, email: "cust_#{SecureRandom.hex(4)}@example.com")
    pm = PaymentMethod.create!(customer: cust, method_type: 'card', last4: '4242', brand: 'Visa', exp_month: 12, exp_year: 2026)
    pi1 = PaymentIntent.create!(merchant: m, customer: cust, payment_method: pm, amount_cents: 5000, currency: 'USD', status: 'authorized')
    pi2 = PaymentIntent.create!(merchant: m, customer: cust, payment_method: pm, amount_cents: 4000, currency: 'USD', status: 'authorized')
    Transaction.create!(payment_intent: pi1, kind: 'authorize', status: 'succeeded', amount_cents: 5000)
    Transaction.create!(payment_intent: pi2, kind: 'authorize', status: 'succeeded', amount_cents: 4000)

    idempotency_key = 'cap-cross-pi-key'

    post "/api/v1/payment_intents/#{pi1.id}/capture",
         params: { idempotency_key: idempotency_key },
         headers: api_headers(key),
         as: :json
    expect(response).to have_http_status(:ok)

    post "/api/v1/payment_intents/#{pi2.id}/capture",
         params: { idempotency_key: idempotency_key },
         headers: api_headers(key),
         as: :json
    expect(response).to have_http_status(:conflict)
  end

  it 'returns 409 when the same idempotency key is reused for refund with a different amount' do
    m, key = create_merchant_with_api_key
    cust = Customer.create!(merchant: m, email: "cust_#{SecureRandom.hex(4)}@example.com")
    pm = PaymentMethod.create!(customer: cust, method_type: 'card', last4: '4242', brand: 'Visa', exp_month: 12, exp_year: 2026)
    pi = PaymentIntent.create!(merchant: m, customer: cust, payment_method: pm, amount_cents: 5000, currency: 'USD', status: 'captured')
    Transaction.create!(payment_intent: pi, kind: 'authorize', status: 'succeeded', amount_cents: 5000)
    Transaction.create!(payment_intent: pi, kind: 'capture', status: 'succeeded', amount_cents: 5000)

    idempotency_key = 'refund-amount-mismatch'

    post "/api/v1/payment_intents/#{pi.id}/refunds",
         params: { refund: { amount_cents: 1000 }, idempotency_key: idempotency_key },
         headers: api_headers(key),
         as: :json
    expect(response).to have_http_status(:created)

    post "/api/v1/payment_intents/#{pi.id}/refunds",
         params: { refund: { amount_cents: 2000 }, idempotency_key: idempotency_key },
         headers: api_headers(key),
         as: :json
    expect(response).to have_http_status(:conflict)
    expect(pi.reload.transactions.where(kind: 'refund', status: 'succeeded').count).to eq(1)
  end

  it 'returns 409 when create payment intent idempotency key is reused with different body' do
    m, key = create_merchant_with_api_key
    cust = Customer.create!(merchant: m, email: "cust_#{SecureRandom.hex(4)}@example.com")
    pm = PaymentMethod.create!(customer: cust, method_type: 'card', last4: '4242', brand: 'Visa', exp_month: 12, exp_year: 2026)

    idempotency_key = 'pi-create-mismatch'
    payload_a = {
      payment_intent: {
        customer_id: cust.id,
        payment_method_id: pm.id,
        amount_cents: 1200,
        currency: 'usd',
        idempotency_key: idempotency_key
      }
    }
    payload_b = payload_a.deep_dup
    payload_b[:payment_intent][:amount_cents] = 3400

    post '/api/v1/payment_intents',
         params: payload_a,
         headers: api_headers(key),
         as: :json
    expect(response).to have_http_status(:created)

    post '/api/v1/payment_intents',
         params: payload_b,
         headers: api_headers(key),
         as: :json
    expect(response).to have_http_status(:conflict)
    expect(m.reload.payment_intents.count).to eq(1)
  end

  it 'allows the same idempotency key string for different merchants (tenant isolation)' do
    m_a, key_a = create_merchant_with_api_key(name: 'A', email: "a_#{SecureRandom.hex(4)}@example.com")
    m_b, key_b = create_merchant_with_api_key(name: 'B', email: "b_#{SecureRandom.hex(4)}@example.com")

    cust_a = Customer.create!(merchant: m_a, email: "ca_#{SecureRandom.hex(4)}@example.com")
    pm_a = PaymentMethod.create!(customer: cust_a, method_type: 'card', last4: '4242', brand: 'Visa', exp_month: 12, exp_year: 2026)
    pi_a = PaymentIntent.create!(merchant: m_a, customer: cust_a, payment_method: pm_a, amount_cents: 2000, currency: 'USD', status: 'created')

    cust_b = Customer.create!(merchant: m_b, email: "cb_#{SecureRandom.hex(4)}@example.com")
    pm_b = PaymentMethod.create!(customer: cust_b, method_type: 'card', last4: '4242', brand: 'Visa', exp_month: 12, exp_year: 2026)
    pi_b = PaymentIntent.create!(merchant: m_b, customer: cust_b, payment_method: pm_b, amount_cents: 2000, currency: 'USD', status: 'created')

    shared_key = 'shared-idem-key-tenant'

    post "/api/v1/payment_intents/#{pi_a.id}/authorize",
         params: { idempotency_key: shared_key },
         headers: api_headers(key_a),
         as: :json
    expect(response).to have_http_status(:ok)

    post "/api/v1/payment_intents/#{pi_b.id}/authorize",
         params: { idempotency_key: shared_key },
         headers: api_headers(key_b),
         as: :json
    expect(response).to have_http_status(:ok)
  end

  it 'allows the same idempotency key for authorize then capture (endpoint isolation)' do
    m, key = create_merchant_with_api_key
    cust = Customer.create!(merchant: m, email: "cust_#{SecureRandom.hex(4)}@example.com")
    pm = PaymentMethod.create!(customer: cust, method_type: 'card', last4: '4242', brand: 'Visa', exp_month: 12, exp_year: 2026)
    pi = PaymentIntent.create!(merchant: m, customer: cust, payment_method: pm, amount_cents: 5000, currency: 'USD', status: 'created')

    shared_key = 'same-key-different-endpoint'

    post "/api/v1/payment_intents/#{pi.id}/authorize",
         params: { idempotency_key: shared_key },
         headers: api_headers(key),
         as: :json
    expect(response).to have_http_status(:ok)

    pi.reload
    expect(pi.status).to eq('authorized')

    post "/api/v1/payment_intents/#{pi.id}/capture",
         params: { idempotency_key: shared_key },
         headers: api_headers(key),
         as: :json
    expect(response).to have_http_status(:ok)
    expect(pi.reload.status).to eq('captured')
  end
end
