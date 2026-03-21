# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Skills::SkillResult do
  describe '.success' do
    it 'builds a successful result with stable to_h' do
      r = described_class.success(
        skill_key: :docs_lookup,
        data: { 'rows' => 1 },
        explanation: 'ok',
        metadata: { agent_key: 'support_faq' },
        deterministic: true
      )
      expect(r.success).to be(true)
      expect(r.skill_key).to eq(:docs_lookup)
      expect(r.data).to eq({ 'rows' => 1 })
      expect(r.to_h[:skill_key]).to eq('docs_lookup')
      expect(r.to_h[:deterministic]).to be(true)
      expect(r.to_h[:safe_for_composition]).to be(true)
    end
  end

  describe '.failure' do
    it 'builds a failure with safe error fields' do
      r = described_class.failure(
        skill_key: :docs_lookup,
        error_code: 'skill_not_allowed',
        error_message: 'Not allowed.'
      )
      expect(r.success).to be(false)
      expect(r.failure?).to be(true)
      expect(r.error_code).to eq('skill_not_allowed')
      h = r.to_h
      expect(h).not_to have_key(:data)
      expect(h[:error_code]).to eq('skill_not_allowed')
    end
  end
end
