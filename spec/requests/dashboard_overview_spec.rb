# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Dashboard Overview', type: :request do
  include ApiHelpers

  before { stub_processor_success; stub_webhook_delivery }

  def csrf_token
    get dashboard_sign_in_path
    response.body[/name="csrf-token" content="([^"]+)"/, 1] || response.body[/name="authenticity_token" value="([^"]+)"/, 1]
  end

  def sign_in_merchant(merchant, api_key)
    post dashboard_sign_in_path, params: { api_key: api_key, authenticity_token: csrf_token }
    follow_redirect! if response.redirect?
  end

  it 'currency "usd" is normalized to "USD" and totals appear in LedgerSummary and Dashboard Overview' do
    merchant, api_key = create_merchant_with_api_key
    cust = Customer.create!(merchant: merchant, email: "cust_#{SecureRandom.hex(4)}@example.com")
    pm = PaymentMethod.create!(customer: cust, method_type: 'card', last4: '4242', brand: 'Visa', exp_month: 12, exp_year: 2026)

    # Create PI with lowercase "usd" (simulates dashboard form)
    post '/api/v1/payment_intents',
         params: { payment_intent: { customer_id: cust.id, payment_method_id: pm.id, amount_cents: 5_000, currency: 'usd' } },
         headers: api_headers(api_key),
         as: :json
    expect(response).to have_http_status(:created)
    pi_id = response.parsed_body['data']['id']

    post "/api/v1/payment_intents/#{pi_id}/authorize", params: { idempotency_key: 'regress-auth' }, headers: api_headers(api_key), as: :json
    expect(response).to have_http_status(:ok)

    post "/api/v1/payment_intents/#{pi_id}/capture", params: { idempotency_key: 'regress-cap' }, headers: api_headers(api_key), as: :json
    expect(response).to have_http_status(:ok)

    entry = LedgerEntry.find_by(merchant: merchant, entry_type: 'charge')
    expect(entry).to be_present
    expect(entry.currency).to eq('USD')
    expect(entry.amount_cents).to eq(5_000)

    result = Reporting::LedgerSummary.new(
      merchant_id: merchant.id,
      from: 1.year.ago,
      to: Time.current,
      currency: 'USD'
    ).call
    expect(result[:totals][:charges_cents]).to eq(5_000)

    sign_in_merchant(merchant, api_key)
    get dashboard_overview_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('$50.00')
  end

  it 'shows financial totals from LedgerEntry (charge +1000, refund -500)' do
    merchant, api_key = create_merchant_with_api_key
    LedgerEntry.where(merchant: merchant).delete_all

    LedgerEntry.create!(merchant: merchant, entry_type: 'charge', amount_cents: 1_000, currency: 'USD')
    LedgerEntry.create!(merchant: merchant, entry_type: 'refund', amount_cents: -500, currency: 'USD')

    sign_in_merchant(merchant, api_key)
    get dashboard_overview_path

    expect(response).to have_http_status(:ok)
    body = response.body
    # Captured Volume: $10.00
    expect(body).to include('$10.00')
    # Refunded: $5.00 (stored as -500, displayed as positive)
    expect(body).to include('$5.00')
    # Net: charges - refunds = 1000 - 500 = 500 cents = $5.00
    expect(body).to include('text-success') # net >= 0
  end
end
