# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Skills::PlatformV1 do
  it 'defines version labels' do
    expect(described_class::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
    expect(described_class::CONTRACT_SCHEMA_VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end

  it 'lists official keys aligned with registries' do
    expect(described_class.official_skill_keys).to eq(Ai::Skills::Registry::SKILLS.keys.map(&:to_sym).sort)
    expect(described_class.official_workflow_keys).to eq(Ai::Skills::Workflows::Registry.keys.map(&:to_sym).sort)
  end

  it 'keeps contract schema constants in sync with PlatformV1' do
    expect(Ai::Skills::SkillResult::CONTRACT_SCHEMA_VERSION).to eq(described_class::CONTRACT_SCHEMA_VERSION)
    expect(Ai::Skills::CompositionResult::CONTRACT_SCHEMA_VERSION).to eq(described_class::CONTRACT_SCHEMA_VERSION)
    expect(Ai::Skills::Workflows::WorkflowResult::CONTRACT_SCHEMA_VERSION).to eq(described_class::CONTRACT_SCHEMA_VERSION)
  end

  it 'matches invocation phases to InvocationContext' do
    expect(described_class::INVOCATION_PHASES).to eq(Ai::Skills::InvocationContext::PHASES)
  end

  it 'validate! passes in test (registry, profiles, workflows, slots)' do
    expect { described_class.validate! }.not_to raise_error
  end

  it 'documents v1 platform file exists' do
    expect(Rails.root.join('docs/AI_SKILL_PLATFORM_V1.md')).to exist
  end

  it 'reserved non-v1 slot keys are not in Registry' do
    Ai::Skills::ResponseSlots::RESERVED_NON_V1_SKILL_KEYS.each do |k|
      expect(Ai::Skills::Registry.known?(k)).to be(false)
    end
  end
end
