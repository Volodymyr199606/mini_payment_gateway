# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Payments::Providers::StripeAdapter do
  let(:adapter) { described_class.new }

  around do |example|
    old_key = ENV['STRIPE_SECRET_KEY']
    old_secret = ENV['STRIPE_WEBHOOK_SECRET']
    ENV['STRIPE_SECRET_KEY'] = 'sk_test_123'
    ENV['STRIPE_WEBHOOK_SECRET'] = 'whsec_test_secret'
    example.run
    ENV['STRIPE_SECRET_KEY'] = old_key
    ENV['STRIPE_WEBHOOK_SECRET'] = old_secret
  end

  it 'verifies stripe webhook signatures' do
    payload = { type: 'payment_intent.succeeded', data: { object: { id: 'pi_123', metadata: { 'merchant_id' => '1' } } } }.to_json
    timestamp = Time.now.to_i
    signed_payload = "#{timestamp}.#{payload}"
    digest = OpenSSL::HMAC.hexdigest('SHA256', ENV['STRIPE_WEBHOOK_SECRET'], signed_payload)
    headers = { 'Stripe-Signature' => "t=#{timestamp},v1=#{digest}" }

    expect(adapter.verify_webhook_signature(payload: payload, headers: headers)).to be(true)
  end

  it 'normalizes stripe webhook event to internal contract' do
    payload = {
      'id' => 'evt_123',
      'type' => 'payment_intent.succeeded',
      'created' => Time.now.to_i,
      'data' => {
        'object' => {
          'id' => 'pi_123',
          'metadata' => {
            'merchant_id' => '44',
            'internal_payment_intent_id' => '77'
          }
        }
      }
    }

    normalized = adapter.normalize_webhook_event(payload: payload, headers: { 'Stripe-Signature' => 'sig' })
    expect(normalized[:event_type]).to eq('transaction.succeeded')
    expect(normalized[:merchant_id]).to eq('44')
    expect(normalized[:payload].dig(:data, :payment_intent_id)).to eq('77')
  end

  it 'normalizes charge.dispute.created with provider_payment_intent_id from charge' do
    payload = {
      'id' => 'evt_disp',
      'type' => 'charge.dispute.created',
      'data' => {
        'object' => {
          'id' => 'dp_123',
          'charge' => { 'payment_intent' => 'pi_stripe_456' }
        }
      }
    }
    normalized = adapter.normalize_webhook_event(payload: payload, headers: {})
    expect(normalized[:event_type]).to eq('chargeback.opened')
    expect(normalized[:payload].dig(:data, :provider_payment_intent_id)).to eq('pi_stripe_456')
  end

  describe 'provider operations' do
    it 'capture returns missing_reference_result when no authorize processor_ref' do
      m = Merchant.create_with_api_key(name: 'T', status: 'active', email: "t_#{SecureRandom.hex(4)}@example.com", password: 'pass123', password_confirmation: 'pass123').first
      c = Customer.create!(merchant: m, email: "c_#{SecureRandom.hex(4)}@example.com")
      pm = PaymentMethod.create!(customer: c, method_type: 'card', last4: '4242', token: 'pm_card_visa', brand: 'Visa', exp_month: 12, exp_year: 2026)
      pi = PaymentIntent.create!(merchant: m, customer: c, payment_method: pm, amount_cents: 5000, currency: 'USD', status: 'created')

      result = adapter.capture(payment_intent: pi)

      expect(result.success?).to be(false)
      expect(result.failure_code).to eq('missing_processor_reference')
    end

    it 'void returns missing_reference_result when no authorize processor_ref' do
      m = Merchant.create_with_api_key(name: 'T', status: 'active', email: "t_#{SecureRandom.hex(4)}@example.com", password: 'pass123', password_confirmation: 'pass123').first
      c = Customer.create!(merchant: m, email: "c_#{SecureRandom.hex(4)}@example.com")
      pm = PaymentMethod.create!(customer: c, method_type: 'card', last4: '4242', token: 'pm_card_visa', brand: 'Visa', exp_month: 12, exp_year: 2026)
      pi = PaymentIntent.create!(merchant: m, customer: c, payment_method: pm, amount_cents: 5000, currency: 'USD', status: 'created')

      result = adapter.void(payment_intent: pi)

      expect(result.success?).to be(false)
      expect(result.failure_code).to eq('missing_processor_reference')
    end
  end
end
