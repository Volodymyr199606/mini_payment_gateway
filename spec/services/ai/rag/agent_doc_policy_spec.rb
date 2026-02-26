# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Rag::AgentDocPolicy do
  describe '.for_agent' do
    it 'returns allowed and preferred for operational' do
      policy = described_class.for_agent(:operational)
      expect(policy[:allowed]).to include('docs/PAYMENT_LIFECYCLE.md', 'docs/ARCHITECTURE.md', 'docs/DATA_FLOW.md')
      expect(policy[:preferred]).to include('docs/PAYMENT_LIFECYCLE.md', 'docs/ARCHITECTURE.md')
    end

    it 'returns allowed and preferred for developer_onboarding' do
      policy = described_class.for_agent(:developer_onboarding)
      expect(policy[:allowed]).to include('docs/REFUNDS_API.md', 'docs/ARCHITECTURE.md')
      expect(policy[:preferred]).to include('docs/REFUNDS_API.md')
    end

    it 'returns allowed and preferred for security_compliance' do
      policy = described_class.for_agent(:security_compliance)
      expect(policy[:allowed]).to eq(%w[docs/SECURITY.md docs/PCI_COMPLIANCE.md])
      expect(policy[:preferred]).to eq(%w[docs/SECURITY.md docs/PCI_COMPLIANCE.md])
    end

    it 'returns allowed and preferred for support_faq' do
      policy = described_class.for_agent(:support_faq)
      expect(policy[:allowed]).to include('docs/PAYMENT_LIFECYCLE.md', 'docs/ARCHITECTURE.md')
      expect(policy[:preferred]).to include('docs/PAYMENT_LIFECYCLE.md')
    end

    it 'returns allowed and preferred for reconciliation_analyst' do
      policy = described_class.for_agent(:reconciliation_analyst)
      expect(policy[:allowed]).to include('docs/CHARGEBACKS.md')
      expect(policy[:preferred]).to include('docs/CHARGEBACKS.md')
    end

    it 'returns minimal allowed for reporting_calculation' do
      policy = described_class.for_agent(:reporting_calculation)
      expect(policy[:allowed]).to eq(%w[docs/AI_AGENTS.md])
      expect(policy[:preferred]).to eq(%w[docs/AI_AGENTS.md])
    end

    it 'returns allowed nil and preferred [] for unknown agent' do
      policy = described_class.for_agent(:unknown_agent)
      expect(policy[:allowed]).to be_nil
      expect(policy[:preferred]).to eq([])
    end

    it 'accepts string agent key' do
      policy = described_class.for_agent('operational')
      expect(policy[:allowed]).to include('docs/PAYMENT_LIFECYCLE.md')
    end
  end

  describe '.allowed_files' do
    it 'returns allowed list for known agent' do
      expect(described_class.allowed_files(:operational)).to include('docs/PAYMENT_LIFECYCLE.md')
    end

    it 'returns nil for unknown agent' do
      expect(described_class.allowed_files(:unknown)).to be_nil
    end
  end

  describe '.preferred_files' do
    it 'returns preferred list for known agent' do
      expect(described_class.preferred_files(:operational)).to include('docs/PAYMENT_LIFECYCLE.md')
    end

    it 'returns empty array for unknown agent' do
      expect(described_class.preferred_files(:unknown)).to eq([])
    end
  end
end
