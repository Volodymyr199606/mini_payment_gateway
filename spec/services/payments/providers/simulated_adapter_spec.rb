# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Payments::Providers::SimulatedAdapter do
  let(:adapter) { described_class.new }
  let(:merchant) { Merchant.create_with_api_key(name: 'T', status: 'active', email: "t_#{SecureRandom.hex(4)}@example.com", password: 'pass123', password_confirmation: 'pass123').first }
  let(:customer) { Customer.create!(merchant: merchant, email: "c_#{SecureRandom.hex(4)}@example.com") }
  let(:payment_method) { PaymentMethod.create!(customer: customer, method_type: 'card', last4: '4242', token: 'pm_x', brand: 'Visa', exp_month: 12, exp_year: 2026) }
  let(:payment_intent) { PaymentIntent.create!(merchant: merchant, customer: customer, payment_method: payment_method, amount_cents: 5000, currency: 'USD', status: 'created') }

  it_behaves_like 'implements provider adapter contract'

  it 'authorize returns success or failure (probabilistic)' do
    result = adapter.authorize(payment_intent: payment_intent)
    expect(result).to be_a(Payments::ProviderResult)
    expect([true, false]).to include(result.success?)
    expect(result.processor_ref).to be_present if result.success?
  end

  it 'verify_webhook_signature validates against webhook_secret' do
    payload = { event_type: 'test' }.to_json
    sig = WebhookSignatureService.generate_signature(payload, Rails.application.config.webhook_secret)
    expect(adapter.verify_webhook_signature(payload: payload, headers: { 'X-WEBHOOK-SIGNATURE' => sig })).to be(true)
  end
end
