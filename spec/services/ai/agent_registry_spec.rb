# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::AgentRegistry do
  describe '.fetch' do
    it 'resolves known keys to the correct agent classes' do
      expect(described_class.fetch(:support_faq)).to eq(Ai::Agents::SupportFaqAgent)
      expect(described_class.fetch(:security_compliance)).to eq(Ai::Agents::SecurityAgent)
      expect(described_class.fetch(:developer_onboarding)).to eq(Ai::Agents::OnboardingAgent)
      expect(described_class.fetch(:operational)).to eq(Ai::Agents::OperationalAgent)
      expect(described_class.fetch(:reconciliation_analyst)).to eq(Ai::Agents::ReconciliationAgent)
      expect(described_class.fetch(:reporting_calculation)).to eq(Ai::Agents::ReportingCalculationAgent)
    end

    it 'accepts string keys and normalizes to symbol' do
      expect(described_class.fetch('support_faq')).to eq(Ai::Agents::SupportFaqAgent)
    end

    it 'raises a helpful error for unknown keys' do
      expect { described_class.fetch(:unknown_agent) }.to raise_error(Ai::AgentRegistry::UnknownAgentError) do |e|
        expect(e.message).to include('Unknown agent key')
        expect(e.message).to include(':unknown_agent')
        expect(e.message).to include('support_faq')
        expect(e.message).to include('reporting_calculation')
      end
    end
  end

  describe '.all_keys' do
    it 'returns all registered agent keys as symbols' do
      keys = described_class.all_keys
      expect(keys).to contain_exactly(
        :support_faq,
        :security_compliance,
        :developer_onboarding,
        :operational,
        :reconciliation_analyst,
        :reporting_calculation
      )
    end
  end

  describe '.default_key' do
    it 'returns :support_faq' do
      expect(described_class.default_key).to eq(:support_faq)
    end
  end

  describe '.definition' do
    it 'returns AgentDefinition for known key' do
      d = described_class.definition(:support_faq)
      expect(d).to be_a(Ai::Agents::AgentDefinition)
      expect(d.key).to eq(:support_faq)
      expect(d.debug_label).to eq('Support FAQ')
      expect(d.supports_retrieval?).to be true
      expect(d.supports_memory?).to be true
    end

    it 'returns definition for reporting_calculation with supports_retrieval false' do
      d = described_class.definition(:reporting_calculation)
      expect(d).to be_a(Ai::Agents::AgentDefinition)
      expect(d.supports_retrieval?).to be false
      expect(d.supports_memory?).to be false
    end

    it 'returns nil for unknown key' do
      expect(described_class.definition(:unknown)).to be_nil
    end
  end

  describe '.definitions' do
    it 'returns one definition per registered agent' do
      expect(described_class.definitions.size).to eq(described_class.all_keys.size)
    end
  end

  describe '.validate!' do
    it 'does not raise with current registry and definitions' do
      expect { described_class.validate! }.not_to raise_error
      expect(described_class.validate!).to be true
    end
  end
end
