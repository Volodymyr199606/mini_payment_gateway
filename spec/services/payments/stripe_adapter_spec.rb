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
end
