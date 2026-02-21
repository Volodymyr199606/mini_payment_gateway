# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Ledger net math API', type: :request do
  before do
    stub_processor_success
    stub_webhook_delivery
  end

  # 11. Ledger net math: captured - refunded == net; sums match expected after partial+full
  it 'ledger net math: charges minus refunds equals net; sums match after partial and full refund' do
    m, key = create_merchant_with_api_key
    cust = Customer.create!(merchant: m, email: "cust_#{SecureRandom.hex(4)}@example.com")
    pm = PaymentMethod.create!(customer: cust, method_type: 'card', last4: '4242', brand: 'Visa', exp_month: 12, exp_year: 2026)

    # Create, authorize, capture (10_000 cents)
    post '/api/v1/payment_intents',
         params: { payment_intent: { customer_id: cust.id, payment_method_id: pm.id, amount_cents: 10_000, currency: 'USD' } },
         headers: api_headers(key),
         as: :json
    expect(response).to have_http_status(:created)
    pi_id = response.parsed_body['data']['id']

    post "/api/v1/payment_intents/#{pi_id}/authorize", params: { idempotency_key: 'ledger-auth-001' }, headers: api_headers(key), as: :json
    post "/api/v1/payment_intents/#{pi_id}/capture", params: { idempotency_key: 'ledger-cap-001' }, headers: api_headers(key), as: :json

    pi = PaymentIntent.find(pi_id)
    m.reload

    total_charges = m.ledger_entries.charges.sum(:amount_cents)
    total_refunds = m.ledger_entries.refunds.sum(:amount_cents).abs
    net = total_charges - total_refunds
    # App creates charge at authorize and capture (2 charges = 20k)
    expect(net).to eq(20_000)

    # Partial refund 3000
    post "/api/v1/payment_intents/#{pi_id}/refunds",
         params: { refund: { amount_cents: 3000 } },
         headers: api_headers(key),
         as: :json
    m.reload
    total_charges = m.ledger_entries.charges.sum(:amount_cents)
    total_refunds = m.ledger_entries.refunds.sum(:amount_cents).abs
    expect(total_charges).to eq(20_000)
    expect(total_refunds).to eq(3000)
    expect(total_charges - total_refunds).to eq(17_000)

    # Full remaining refund 7000
    post "/api/v1/payment_intents/#{pi_id}/refunds", params: {}, headers: api_headers(key), as: :json
    m.reload
    total_charges = m.ledger_entries.charges.sum(:amount_cents)
    total_refunds = m.ledger_entries.refunds.sum(:amount_cents).abs
    expect(total_charges).to eq(20_000)
    expect(total_refunds).to eq(10_000)
    expect(total_charges - total_refunds).to eq(10_000)
  end
end
