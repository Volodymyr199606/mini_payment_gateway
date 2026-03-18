# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ExecutionPlan contract' do
  let(:valid_modes) { %w[deterministic_only docs_only tool_plus_docs agent_full no_memory no_retrieval concise_rewrite_only] }

  describe 'to_audit_metadata' do
    it 'includes all required keys and contract_version' do
      plan = Ai::Performance::ExecutionPlan.new(
        execution_mode: :deterministic_only,
        skip_retrieval: true,
        skip_memory: true,
        skip_orchestration: false,
        retrieval_budget_reduced: false,
        reason_codes: %w[intent_present],
        metadata: {}
      )
      meta = plan.to_audit_metadata
      AiContractHelpers.assert_required_keys!(
        meta,
        %i[execution_mode retrieval_skipped memory_skipped orchestration_skipped retrieval_budget_reduced reason_codes contract_version],
        contract_name: 'ExecutionPlan.to_audit_metadata'
      )
      expect(meta[:contract_version]).to eq(Ai::Contracts::EXECUTION_PLAN_VERSION)
    end

    it 'has execution_mode as valid enum' do
      plan = Ai::Performance::ExecutionPlan.full_agent
      meta = plan.to_audit_metadata
      AiContractHelpers.assert_enum!(
        meta[:execution_mode],
        valid_modes,
        contract_name: 'ExecutionPlan',
        field_name: 'execution_mode'
      )
    end

    it 'has boolean flags for retrieval_skipped, memory_skipped, retrieval_budget_reduced' do
      plan = Ai::Performance::ExecutionPlan.new(
        execution_mode: :agent_full,
        skip_retrieval: false,
        skip_memory: true,
        skip_orchestration: true,
        retrieval_budget_reduced: true,
        reason_codes: [],
        metadata: {}
      )
      meta = plan.to_audit_metadata
      expect(meta[:retrieval_skipped]).to be_in([true, false])
      expect(meta[:memory_skipped]).to be_in([true, false])
      expect(meta[:retrieval_budget_reduced]).to be_in([true, false])
      expect(meta[:reason_codes]).to be_a(Array)
    end

    it 'does not expose sensitive fields' do
      plan = Ai::Performance::ExecutionPlan.full_agent
      AiContractHelpers.assert_no_forbidden_keys!(plan.to_audit_metadata, contract_name: 'ExecutionPlan')
    end
  end

  describe 'to_h' do
    it 'includes contract_version and stable keys' do
      plan = Ai::Performance::ExecutionPlan.full_agent
      h = plan.to_h
      expect(h).to have_key(:contract_version)
      expect(h).to have_key(:execution_mode)
      expect(h).to have_key(:skip_retrieval)
      expect(h).to have_key(:skip_memory)
      expect(h[:metadata]).to be_a(Hash)
    end
  end
end
