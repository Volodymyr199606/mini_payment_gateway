# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Merchant scoping API', type: :request do
  before do
    stub_processor_success
    stub_webhook_delivery
  end

  # 12. Merchant scoping: merchant B cannot read/operate on merchant A's intent/txn (404 or 403)
  it 'merchant B cannot read or operate on merchant A payment intent (404)' do
    m_a, key_a = create_merchant_with_api_key(name: 'Merchant A', email: "merchant_a_#{SecureRandom.hex(4)}@example.com")
    m_b, key_b = create_merchant_with_api_key(name: 'Merchant B', email: "merchant_b_#{SecureRandom.hex(4)}@example.com")

    cust_a = Customer.create!(merchant: m_a, email: "cust_a_#{SecureRandom.hex(4)}@example.com")
    pm_a = PaymentMethod.create!(customer: cust_a, method_type: 'card', last4: '4242', brand: 'Visa', exp_month: 12, exp_year: 2026)
    pi_a = PaymentIntent.create!(merchant: m_a, customer: cust_a, payment_method: pm_a, amount_cents: 5000, currency: 'USD', status: 'created')

    # Merchant B tries to show Merchant A's payment intent
    get "/api/v1/payment_intents/#{pi_a.id}", headers: api_headers(key_b), as: :json
    expect(response).to have_http_status(:not_found)

    # Merchant B tries to authorize Merchant A's payment intent
    post "/api/v1/payment_intents/#{pi_a.id}/authorize", params: { idempotency_key: 'scope-test' }, headers: api_headers(key_b), as: :json
    expect(response).to have_http_status(:not_found)

    # Merchant B tries to capture Merchant A's payment intent (if it were authorized)
    pi_a.update!(status: 'authorized')
    Transaction.create!(payment_intent: pi_a, kind: 'authorize', status: 'succeeded', amount_cents: 5000)
    post "/api/v1/payment_intents/#{pi_a.id}/capture", params: { idempotency_key: 'scope-test-cap' }, headers: api_headers(key_b), as: :json
    expect(response).to have_http_status(:not_found)
  end
end
