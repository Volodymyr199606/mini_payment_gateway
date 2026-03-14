# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Performance::ExecutionPlan do
  describe 'Struct behavior' do
    it 'exposes execution_mode, skip_retrieval, skip_memory, reason_codes' do
      plan = described_class.new(
        execution_mode: :deterministic_only,
        skip_retrieval: true,
        skip_memory: true,
        skip_orchestration: false,
        retrieval_budget_reduced: false,
        reason_codes: %w[intent_present deterministic_sufficient],
        metadata: {}
      )
      expect(plan.execution_mode).to eq(:deterministic_only)
      expect(plan.skip_retrieval).to be true
      expect(plan.skip_memory).to be true
      expect(plan.skip_orchestration).to be false
      expect(plan.reason_codes).to eq(%w[intent_present deterministic_sufficient])
    end

    it 'retrieval_skipped? returns skip_retrieval value' do
      plan = described_class.new(execution_mode: :agent_full, skip_retrieval: true, skip_memory: false, skip_orchestration: true, retrieval_budget_reduced: false, reason_codes: [], metadata: {})
      expect(plan.retrieval_skipped?).to be true
      plan = described_class.new(execution_mode: :agent_full, skip_retrieval: false, skip_memory: false, skip_orchestration: true, retrieval_budget_reduced: false, reason_codes: [], metadata: {})
      expect(plan.retrieval_skipped?).to be false
    end

    it 'memory_skipped? returns skip_memory value' do
      plan = described_class.new(execution_mode: :agent_full, skip_retrieval: false, skip_memory: true, skip_orchestration: true, retrieval_budget_reduced: false, reason_codes: [], metadata: {})
      expect(plan.memory_skipped?).to be true
      plan = described_class.new(execution_mode: :agent_full, skip_retrieval: false, skip_memory: false, skip_orchestration: true, retrieval_budget_reduced: false, reason_codes: [], metadata: {})
      expect(plan.memory_skipped?).to be false
    end

    it 'orchestration_skipped? returns skip_orchestration value' do
      plan = described_class.new(execution_mode: :agent_full, skip_retrieval: false, skip_memory: false, skip_orchestration: true, retrieval_budget_reduced: false, reason_codes: [], metadata: {})
      expect(plan.orchestration_skipped?).to be true
    end
  end

  describe '.full_agent' do
    it 'returns full agent plan with no skips' do
      plan = described_class.full_agent
      expect(plan.execution_mode).to eq(:agent_full)
      expect(plan.skip_retrieval).to be false
      expect(plan.skip_memory).to be false
      expect(plan.skip_orchestration).to be false
      expect(plan.retrieval_budget_reduced).to be false
    end
  end

  describe '#to_audit_metadata' do
    it 'returns hash with execution_mode, retrieval_skipped, memory_skipped, reason_codes' do
      plan = described_class.new(
        execution_mode: :deterministic_only,
        skip_retrieval: true,
        skip_memory: true,
        skip_orchestration: false,
        retrieval_budget_reduced: false,
        reason_codes: %w[intent_present],
        metadata: nil
      )
      meta = plan.to_audit_metadata
      expect(meta[:execution_mode]).to eq('deterministic_only')
      expect(meta[:retrieval_skipped]).to be true
      expect(meta[:memory_skipped]).to be true
      expect(meta[:orchestration_skipped]).to be false
      expect(meta[:retrieval_budget_reduced]).to be false
      expect(meta[:reason_codes]).to eq(%w[intent_present])
    end

    it 'handles nil reason_codes' do
      plan = described_class.new(
        execution_mode: :agent_full,
        skip_retrieval: false,
        skip_memory: false,
        skip_orchestration: true,
        retrieval_budget_reduced: false,
        reason_codes: nil,
        metadata: {}
      )
      meta = plan.to_audit_metadata
      expect(meta[:reason_codes]).to eq([])
    end
  end
end
