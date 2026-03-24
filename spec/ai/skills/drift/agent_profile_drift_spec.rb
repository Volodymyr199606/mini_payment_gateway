# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Agent profile skill drift', type: :eval do
  it 'AgentSkillExpectations matches AgentProfiles (YAML contract)' do
    path = Rails.root.join('spec/fixtures/ai/agent_skill_expectations.yml')
    skip unless path.exist?

    ex = Ai::Evals::Skills::AgentSkillExpectations.load(path)
    violations = Ai::Evals::Skills::AgentSkillExpectations.violations(ex)
    expect(violations).to eq([]), violations.join("\n")
  end

  it 'each profile heavy budget is not greater than max_skills_per_request' do
    Ai::Skills::AgentProfiles.all.each do |p|
      expect(p.max_heavy_skills_per_request).to be <= p.max_skills_per_request
    end
  end
end
