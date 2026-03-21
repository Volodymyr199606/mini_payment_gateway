# frozen_string_literal: true

require 'rails_helper'

# Verifies skill safety: merchant scoping, policy boundaries, no leakage.
RSpec.describe 'AI skill safety', type: :eval do
  include ApiHelpers

  describe 'merchant scoping' do
    it 'payment_state_explainer fails when merchant_id missing' do
      result = Ai::Skills::PaymentStateExplainer.new.execute(
        context: { payment_intent_id: 1 }
      )
      expect(result.success).to be(false)
      expect(result.error_code).to eq('missing_context')
    end

    it 'payment_state_explainer uses merchant-scoped lookup' do
      m1 = create_merchant_with_api_key.first
      m2 = create_merchant_with_api_key.first
      c1 = m1.customers.create!(email: "c1_#{SecureRandom.hex(4)}@x.com")
      pi = m1.payment_intents.create!(customer: c1, amount_cents: 1000, currency: 'USD')

      result = Ai::Skills::PaymentStateExplainer.new.execute(
        context: { merchant_id: m2.id, payment_intent_id: pi.id }
      )
      expect(result.success).to be(false)
      expect(result.error_code).to eq('missing_entity')
    end

    it 'Invoker blocks disallowed skill for agent' do
      result = Ai::Skills::Invoker.call(
        agent_key: :developer_onboarding,
        skill_key: :payment_state_explainer,
        context: { merchant_id: 1, message: 'x' }
      )
      expect(result).to be_present
      expect(result.success).to be(false)
      expect(result.error_code).to eq('skill_not_allowed')
    end
  end

  describe 'policy boundary' do
    it 'tool blocks cross-merchant before skill receives data' do
      victim = create_merchant_with_api_key.first
      attacker = create_merchant_with_api_key.first
      c = victim.customers.create!(email: "c_#{SecureRandom.hex(4)}@x.com")
      pi = victim.payment_intents.create!(customer: c, amount_cents: 1000, currency: 'USD')

      result = Ai::Tools::Executor.call(
        tool_name: 'get_payment_intent',
        args: { payment_intent_id: pi.id },
        context: { merchant_id: attacker.id }
      )
      expect(result[:success]).to be(false)
      expect(result[:authorization_denied]).to be(true)
    end
  end

  describe 'output safety' do
    it 'UsageSerializer strips unsafe keys' do
      raw = { skill_key: 'x', phase: 'p', invoked: true, raw_payload: 'secret' }
      normalized = Ai::Skills::UsageSerializer.normalize(raw: raw)
      expect(normalized.first).not_to have_key('raw_payload')
      expect(normalized.first['skill_key']).to eq('x')
    end

    it 'QualityMetadata does not include raw inputs or unsafe keys' do
      meta = Ai::Evals::Skills::QualityMetadata.build(
        skill_key: 'test',
        invoked: true,
        helpful: true
      )
      expect(meta).not_to have_key('raw_payload')
      expect(meta).not_to have_key('internal_prompt')
      expect(meta['skill_key']).to eq('test')
    end
  end
end
