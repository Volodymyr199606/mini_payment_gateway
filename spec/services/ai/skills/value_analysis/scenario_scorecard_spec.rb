# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Skills::ValueAnalysis::ScenarioScorecard do
  describe '.coverage_from_fixtures' do
    it 'maps expected_skill_keys to scenario ids from both fixtures' do
      cov = described_class.coverage_from_fixtures
      expect(cov['payment_state_explainer'][:scenario_ids]).to include('skill-pi-explainer', 'reg-support-pi-explainer')
      expect(cov['ledger_period_summary'][:scenario_count]).to be >= 2
    end
  end

  describe '.eval_pass_rates_by_scenario' do
    it 'normalizes scenario pass flags' do
      h = described_class.eval_pass_rates_by_scenario(
        [{ scenario_id: 'a', passed_overall: true }, { 'scenario_id' => 'b', passed_overall: false }]
      )
      expect(h['a']).to be true
      expect(h['b']).to be false
    end
  end

  describe '.summary' do
    it 'returns stable keys' do
      s = described_class.summary
      expect(s).to include(:skills_covered, :total_scenario_skill_slots, :fixture_paths_resolved)
    end
  end
end
