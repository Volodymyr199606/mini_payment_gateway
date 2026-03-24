# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Skills::AgentProfiles do
  describe '.for' do
    it 'returns profile for each agent' do
      %i[support_faq operational reconciliation_analyst reporting_calculation security_compliance developer_onboarding].each do |agent|
        profile = described_class.for(agent)
        expect(profile).to be_a(Ai::Skills::AgentProfile)
        expect(profile.agent_key).to eq(agent)
      end
    end

    it 'support_faq has max 2 skills, prefers payment_state_explainer' do
      profile = described_class.for(:support_faq)
      expect(profile.max_skills_per_request).to eq(2)
      expect(profile.preferred?(:payment_state_explainer)).to be true
      expect(profile.preference_rank(:payment_state_explainer)).to eq(0)
    end

    it 'reporting_calculation has max 1 skill, suppresses reporting_trend_summary' do
      profile = described_class.for(:reporting_calculation)
      expect(profile.max_skills_per_request).to eq(1)
      expect(profile.suppressed?(:reporting_trend_summary)).to be true
    end

    it 'reconciliation_analyst has max 2 skills, max 1 heavy' do
      profile = described_class.for(:reconciliation_analyst)
      expect(profile.max_skills_per_request).to eq(2)
      expect(profile.max_heavy_skills_per_request).to eq(1)
    end

    it 'security_compliance has max 1 skill' do
      profile = described_class.for(:security_compliance)
      expect(profile.max_skills_per_request).to eq(1)
    end
  end

  describe 'budget enforcement' do
    it 'budget_reached? when invoked count >= max' do
      profile = described_class.for(:reporting_calculation)
      expect(profile.budget_reached?(already_invoked: [:ledger_period_summary])).to be true
    end

    it 'heavy_budget_reached? when heavy count >= max_heavy' do
      profile = described_class.for(:reconciliation_analyst)
      expect(profile.heavy_budget_reached?(already_invoked: [:discrepancy_detector])).to be true
    end
  end
end
