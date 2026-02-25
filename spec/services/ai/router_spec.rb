# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Router do
  it 'returns :security_compliance for PCI/PAN keywords' do
    expect(described_class.new('How do we handle PCI?').call).to eq(:security_compliance)
    expect(described_class.new('Never store PAN').call).to eq(:security_compliance)
  end

  it 'returns :developer_onboarding for integration keywords' do
    expect(described_class.new('How do I use idempotency?').call).to eq(:developer_onboarding)
    expect(described_class.new('curl endpoint for webhook').call).to eq(:developer_onboarding)
  end

  it 'returns :operational for lifecycle keywords' do
    expect(described_class.new('refund status').call).to eq(:operational)
    expect(described_class.new('authorize then capture').call).to eq(:operational)
  end

  it 'returns :reconciliation_analyst for reconciliation keywords' do
    expect(described_class.new('reconciliation settlement').call).to eq(:reconciliation_analyst)
  end

  it 'returns :support_faq for generic message' do
    expect(described_class.new('Hello, what is this?').call).to eq(:support_faq)
  end
end
