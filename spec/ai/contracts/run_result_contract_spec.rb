# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Orchestration::RunResult contract' do
  describe 'to_h shape' do
    it 'includes required keys and contract_version' do
      result = Ai::Orchestration::RunResult.new(
        orchestration_used: true,
        step_count: 1,
        tool_names: ['get_payment_intent'],
        success: true,
        reply_text: 'Done'
      )
      # RunResult adds contract_version in to_h via CONTRACT_VERSION
      h = result.to_h
      AiContractHelpers.assert_required_keys!(
        h,
        %i[orchestration_used step_count tool_names success contract_version],
        contract_name: 'RunResult'
      )
      expect(h[:contract_version]).to eq(Ai::Contracts::RUN_RESULT_VERSION)
      expect(h[:tool_names]).to be_a(Array)
    end

    it 'no_orchestration has stable shape' do
      result = Ai::Orchestration::RunResult.no_orchestration
      h = result.to_h
      expect(h[:orchestration_used]).to eq(false)
      expect(h[:step_count]).to eq(0)
      expect(h).to have_key(:contract_version)
    end

    it 'does not expose sensitive fields' do
      result = Ai::Orchestration::RunResult.new(
        orchestration_used: true,
        step_count: 1,
        tool_names: ['get_ledger_summary'],
        success: true,
        reply_text: 'Summary: 100'
      )
      AiContractHelpers.assert_no_forbidden_keys!(result.to_h, contract_name: 'RunResult')
    end
  end
end
