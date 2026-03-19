# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Payments::ProviderRegistry do
  around do |example|
    original = ENV['PAYMENTS_PROVIDER']
    example.run
    ENV['PAYMENTS_PROVIDER'] = original
    described_class.reset!
  end

  it 'returns simulated adapter by default' do
    ENV.delete('PAYMENTS_PROVIDER')

    adapter = described_class.current
    expect(adapter).to be_a(Payments::Providers::SimulatedAdapter)
  end

  it 'returns stripe adapter when configured' do
    ENV['PAYMENTS_PROVIDER'] = 'stripe_sandbox'
    ENV['STRIPE_SECRET_KEY'] = 'sk_test_123'
    ENV['STRIPE_WEBHOOK_SECRET'] = 'whsec_test'
    Payments::Config.validate!(raise_in_current_env: true)

    adapter = described_class.current
    expect(adapter).to be_a(Payments::Providers::StripeAdapter)
  end

  it 'raises for unknown provider' do
    expect { described_class.build('unknown_provider') }.to raise_error(StandardError, /Unknown payment provider/)
  end
end
