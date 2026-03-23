# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Skills::RefundEligibilityExplainer do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }
  let(:customer) { merchant.customers.create!(email: "re_#{SecureRandom.hex(4)}@example.com") }

  it 'explains refundable amount for captured intent' do
    pi = merchant.payment_intents.create!(customer: customer, amount_cents: 5000, currency: 'USD', status: 'captured')
    result = described_class.new.execute(
      context: { merchant_id: merchant.id, payment_intent_id: pi.id, agent_key: :operational }
    )
    expect(result.success).to be true
    expect(result.explanation).to include('refundable')
  end

  it 'fails without merchant' do
    result = described_class.new.execute(context: { payment_intent_id: 1 })
    expect(result.success).to be false
  end
end
