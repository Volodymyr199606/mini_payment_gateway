# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Skills::Invoker do
  describe '.call' do
    it 'invokes allowed skill for support_faq' do
      result = described_class.call(
        agent_key: :support_faq,
        skill_key: :docs_lookup,
        context: { merchant_id: 1 }
      )
      expect(result).to be_a(Ai::Skills::SkillResult)
      expect(result.success).to be(true)
      expect(result.skill_key).to eq(:docs_lookup)
      expect(result.to_h[:metadata]).to include('agent_key' => 'support_faq')
    end

    it 'returns failure when skill not allowed for agent' do
      result = described_class.call(
        agent_key: :reporting_calculation,
        skill_key: :docs_lookup,
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
  end
end
