# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Evals::Skills::SkillMetadataContract do
  describe 'invocation results (audit / debug)' do
    it 'accepts InvocationResult#to_audit_hash for executed skill' do
      sr = Ai::Skills::SkillResult.success(
        skill_key: :payment_state_explainer,
        explanation: 'ok',
        deterministic: true
      )
      inv = Ai::Skills::InvocationResult.executed(
        skill_key: :payment_state_explainer,
        phase: :post_tool,
        reason_code: 'payment_data_retrieved',
        skill_result: sr
      )
      expect(described_class.invocation_contract_satisfied?(inv.to_audit_hash)).to be(true)
    end

    it 'accepts skipped InvocationResult' do
      inv = Ai::Skills::InvocationResult.skipped(
        skill_key: :ledger_period_summary,
        phase: :post_tool,
        reason_code: 'invocation_threshold_not_met'
      )
      h = inv.to_audit_hash
      expect(described_class.invocation_contract_satisfied?(h)).to be(true)
    end
  end

  describe 'UsageSerializer' do
    it 'minimal usage contract after normalize_one' do
      raw = {
        skill_key: 'payment_state_explainer',
        phase: 'post_tool',
        invoked: true,
        success: true,
        deterministic: true,
        reason_code: 'x',
        affected_final_response: true
      }
      n = Ai::Skills::UsageSerializer.normalize_one(raw, agent_key: 'operational', affected_final_response: true)
      expect(described_class.usage_contract_satisfied?(n)).to be(true)
    end
  end

  describe 'QualityMetadata' do
    it 'exposes stable keys for analytics / quality notes' do
      expect(Ai::Evals::Skills::QualityMetadata::KEYS).to include(
        'skill_invoked', 'skill_affected_response', 'skill_helpful'
      )
    end
  end

  describe 'composition audit hash' do
    it 'CompositionResult#to_audit_hash includes expected stable keys' do
      cr = Ai::Skills::CompositionResult.new(
        reply_text: 'x',
        filled_slots: { 'primary_explanation' => { skill_key: 'a', text: 'b' } },
        contributing_skills: %w[payment_state_explainer],
        composition_mode: 'single'
      )
      h = cr.to_audit_hash
      expect(h).to have_key(:contributing_skills)
      expect(h).to have_key(:filled_response_slots)
    end
  end
end
