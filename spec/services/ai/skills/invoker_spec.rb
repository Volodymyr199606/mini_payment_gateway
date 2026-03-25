# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Skills::Invoker do
  include ApiHelpers
  describe '.call' do
    it 'invokes allowed skill for support_faq' do
      merchant = create_merchant_with_api_key.first
      customer = merchant.customers.create!(email: "invoker_ok_#{SecureRandom.hex(4)}@example.com")
      pi = merchant.payment_intents.create!(customer: customer, amount_cents: 1000, currency: 'USD', status: 'created')
      result = described_class.call(
        agent_key: :support_faq,
        skill_key: :payment_state_explainer,
        context: { merchant_id: merchant.id, payment_intent_id: pi.id }
      )
      expect(result).to be_a(Ai::Skills::SkillResult)
      expect(result.success).to be(true)
      expect(result.skill_key).to eq(:payment_state_explainer)
      expect(result.to_h[:metadata]).to include('agent_key' => 'support_faq')
    end

    it 'returns failure when skill not allowed for agent' do
      result = described_class.call(
        agent_key: :reporting_calculation,
        skill_key: :payment_state_explainer,
        context: {}
      )
      expect(result.success).to be(false)
      expect(result.error_code).to eq('skill_not_allowed')
    end

    it 'returns failure for unknown skill' do
      result = described_class.call(
        agent_key: :support_faq,
        skill_key: :totally_unknown_skill,
        context: {}
      )
      expect(result.success).to be(false)
      expect(result.error_code).to eq('unknown_skill')
    end

    it 'invokes payment_state_explainer with entity data and returns explanation' do
      merchant = create_merchant_with_api_key.first
      customer = merchant.customers.create!(email: "invoker_#{SecureRandom.hex(4)}@example.com")
      pi = merchant.payment_intents.create!(customer: customer, amount_cents: 1000, currency: 'USD', status: 'created')
      result = described_class.call(
        agent_key: :support_faq,
        skill_key: :payment_state_explainer,
        context: { merchant_id: merchant.id, payment_intent_id: pi.id }
      )
      expect(result.success).to be true
      expect(result.explanation).to include('created')
      expect(result.skill_key).to eq(:payment_state_explainer)
    end
  end
end
