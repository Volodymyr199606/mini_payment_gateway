# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuthorizeService do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }
  let(:customer) { Customer.create!(merchant: merchant, email: "cust_#{SecureRandom.hex(4)}@example.com") }
  let(:payment_method) do
    PaymentMethod.create!(
      customer: customer,
      method_type: 'card',
      last4: '4242',
      brand: 'Visa',
      exp_month: 12,
      exp_year: 2030
    )
  end
  let(:payment_intent) do
    PaymentIntent.create!(
      merchant: merchant,
      customer: customer,
      payment_method: payment_method,
      amount_cents: 5000,
      currency: 'USD',
      status: 'created'
    )
  end

  it 'maps provider success into internal transaction and status' do
    adapter = instance_double(Payments::Providers::BaseAdapter)
    allow(adapter).to receive(:authorize).and_return(
      Payments::ProviderResult.new(success: true, processor_ref: 'pi_stripe_123', provider_status: 'requires_capture')
    )
    allow(Payments::ProviderRegistry).to receive(:current).and_return(adapter)

    service = described_class.call(payment_intent: payment_intent)
    expect(service).to be_success
    expect(service.result[:transaction].processor_ref).to eq('pi_stripe_123')
    expect(service.result[:payment_intent].status).to eq('authorized')
  end

  it 'maps provider failure into failed transaction and intent state' do
    adapter = instance_double(Payments::Providers::BaseAdapter)
    allow(adapter).to receive(:authorize).and_return(
      Payments::ProviderResult.new(success: false, failure_code: 'card_declined', failure_message: 'Card declined')
    )
    allow(Payments::ProviderRegistry).to receive(:current).and_return(adapter)

    service = described_class.call(payment_intent: payment_intent)
    expect(service).to be_success
    expect(service.result[:transaction].status).to eq('failed')
    expect(service.result[:transaction].failure_code).to eq('card_declined')
    expect(payment_intent.reload.status).to eq('failed')
  end
end
