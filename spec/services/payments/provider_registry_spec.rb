# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Payments::ProviderRegistry do
  after { described_class.reset! }

  it 'returns SimulatedAdapter when provider is simulated' do
    allow(Payments::Config).to receive(:provider).and_return('simulated')
    described_class.reset!

    adapter = described_class.current

    expect(adapter).to be_a(Payments::Providers::SimulatedAdapter)
  end

  it 'returns StripeAdapter when provider is stripe_sandbox' do
    allow(Payments::Config).to receive(:provider).and_return('stripe_sandbox')
    allow(Payments::Config).to receive(:stripe_api_key).and_return('sk_test_x')
    allow(Payments::Config).to receive(:stripe_webhook_secret).and_return('whsec_x')
    described_class.reset!

    adapter = described_class.current

    expect(adapter).to be_a(Payments::Providers::StripeAdapter)
  end

  it 'raises ProviderConfigurationError for unknown provider' do
    allow(Payments::Config).to receive(:provider).and_return('unknown_provider')
    described_class.reset!

    expect { described_class.current }.to raise_error(Payments::ProviderConfigurationError, /unknown_provider/)
  end

  it 'caches adapter instance' do
    allow(Payments::Config).to receive(:provider).and_return('simulated')
    described_class.reset!

    first = described_class.current
    second = described_class.current

    expect(first).to equal(second)
  end

  it 'rebuilds adapter after reset!' do
    allow(Payments::Config).to receive(:provider).and_return('simulated')
    described_class.reset!

    first = described_class.current
    described_class.reset!
    second = described_class.current

    expect(first).not_to equal(second)
  end
end
