# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Skill quality gate framework' do
  it 'SkillRegressionRunner uses the regression fixture key' do
    path = Rails.root.join('spec/fixtures/ai/skill_regression_scenarios.yml')
    skip unless path.exist?

    scenarios = Ai::Evals::Skills::SkillRegressionRunner.load_scenarios(path)
    expect(scenarios).not_to be_empty
  end

  it 'ScenarioRunner normalizes regression fields' do
    raw = {
      id: 'x',
      user_message: 'hi',
      must_not_include_skills: %w[discrepancy_detector],
      max_invoked_skills: 1
    }
    s = Ai::Evals::ScenarioRunner.send(:normalize_scenario, raw)
    expect(s[:must_not_include_skills]).to eq(['discrepancy_detector'])
    expect(s[:max_invoked_skills]).to eq(1)
  end

  it 'MetricSamples.summarize handles empty' do
    expect(Ai::Evals::Skills::MetricSamples.summarize([])[:count]).to eq(0)
  end

  it 'SkillMetadataContract reports missing keys' do
    missing = Ai::Evals::Skills::SkillMetadataContract.missing_invocation_keys({ skill_key: 'x' })
    expect(missing).not_to be_empty
  end

  it 'ai_skills_ci rake file exists' do
    expect(Rails.root.join('lib/tasks/ai_skills_ci.rake')).to exist
  end

  it 'PlatformV1 validates without drift' do
    expect { Ai::Skills::PlatformV1.validate! }.not_to raise_error
  end
end
