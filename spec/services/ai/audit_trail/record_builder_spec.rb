# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::AuditTrail::RecordBuilder do
  describe '.call' do
    it 'normalizes metadata with required fields' do
      result = described_class.call(
        request_id: 'req-1',
        endpoint: 'dashboard',
        merchant_id: 1,
        agent_key: 'operational',
        success: true
      )
      expect(result[:request_id]).to eq('req-1')
      expect(result[:endpoint]).to eq('dashboard')
      expect(result[:merchant_id]).to eq(1)
      expect(result[:agent_key]).to eq('operational')
      expect(result[:success]).to be(true)
      expect(result[:tool_used]).to be(false)
      expect(result[:tool_names]).to eq([])
      expect(result[:parsed_entities]).to eq({})
      expect(result[:parsed_intent_hints]).to eq({})
    end

    it 'uses unknown agent_key when missing' do
      result = described_class.call(request_id: 'x', endpoint: 'api', agent_key: nil)
      expect(result[:agent_key]).to eq('unknown')
    end

    it 'normalizes composition_mode from composition hash' do
      result = described_class.call(
        request_id: 'r',
        endpoint: 'dashboard',
        agent_key: 'support_faq',
        composition: { composition_mode: 'docs_only' }
      )
      expect(result[:composition_mode]).to eq('docs_only')
    end

    it 'records tool_used and tool_names' do
      result = described_class.call(
        request_id: 'r',
        endpoint: 'dashboard',
        agent_key: 'tool:get_payment_intent',
        tool_used: true,
        tool_names: ['get_payment_intent'],
        success: true
      )
      expect(result[:tool_used]).to be(true)
      expect(result[:tool_names]).to eq(['get_payment_intent'])
    end

    it 'records orchestration fields when orchestration_used true' do
      result = described_class.call(
        request_id: 'r',
        endpoint: 'dashboard',
        agent_key: 'orchestration',
        tool_used: true,
        tool_names: %w[get_transaction get_payment_intent],
        success: true,
        orchestration_used: true,
        orchestration_step_count: 2,
        orchestration_halted_reason: nil
      )
      expect(result[:orchestration_used]).to be(true)
      expect(result[:orchestration_step_count]).to eq(2)
      expect(result[:orchestration_halted_reason]).to be_nil
    end

    it 'omits orchestration fields when orchestration_used false' do
      result = described_class.call(
        request_id: 'r',
        endpoint: 'dashboard',
        agent_key: 'operational',
        success: true
      )
      expect(result).not_to have_key(:orchestration_used)
      expect(result).not_to have_key(:orchestration_step_count)
      expect(result).not_to have_key(:orchestration_halted_reason)
    end

    it 'records fallback, citation_reask, memory, summary' do
      result = described_class.call(
        request_id: 'r',
        endpoint: 'dashboard',
        agent_key: 'operational',
        fallback_used: true,
        citation_reask_used: true,
        memory_used: true,
        summary_used: true,
        success: true
      )
      expect(result[:fallback_used]).to be(true)
      expect(result[:citation_reask_used]).to be(true)
      expect(result[:memory_used]).to be(true)
      expect(result[:summary_used]).to be(true)
    end

    it 'records failure with error_class and error_message' do
      result = described_class.call(
        request_id: 'r',
        endpoint: 'api',
        agent_key: 'operational',
        success: false,
        error_class: 'StandardError',
        error_message: 'Something broke'
      )
      expect(result[:success]).to be(false)
      expect(result[:error_class]).to eq('StandardError')
      expect(result[:error_message]).to eq('Something broke')
    end

    it 'records policy metadata when provided' do
      result = described_class.call(
        request_id: 'r',
        endpoint: 'dashboard',
        agent_key: 'tool:get_payment_intent',
        success: false,
        policy_metadata: {
          authorization_denied: true,
          tool_blocked_by_policy: true,
          followup_inheritance_blocked: false,
          policy_reason_code: 'access_denied'
        }
      )
      expect(result[:authorization_denied]).to be(true)
      expect(result[:tool_blocked_by_policy]).to be(true)
      expect(result[:followup_inheritance_blocked]).to be(false)
      expect(result[:policy_reason_code]).to eq('access_denied')
    end

    it 'omits policy fields when policy_metadata nil' do
      result = described_class.call(
        request_id: 'r',
        endpoint: 'api',
        agent_key: 'operational',
        success: true
      )
      expect(result).not_to have_key(:authorization_denied)
      expect(result).not_to have_key(:tool_blocked_by_policy)
      expect(result).not_to have_key(:followup_inheritance_blocked)
      expect(result).not_to have_key(:policy_reason_code)
    end

    it 'records execution_plan_metadata when provided' do
      result = described_class.call(
        request_id: 'r',
        endpoint: 'dashboard',
        agent_key: 'operational',
        success: true,
        execution_plan_metadata: {
          execution_mode: 'deterministic_only',
          retrieval_skipped: true,
          memory_skipped: true,
          retrieval_budget_reduced: false,
          reason_codes: %w[intent_present]
        }
      )
      expect(result[:execution_mode]).to eq('deterministic_only')
      expect(result[:retrieval_skipped]).to be(true)
      expect(result[:memory_skipped]).to be(true)
      expect(result[:retrieval_budget_reduced]).to be(false)
    end

    it 'omits execution_plan fields when execution_plan_metadata nil' do
      result = described_class.call(
        request_id: 'r',
        endpoint: 'api',
        agent_key: 'operational',
        success: true
      )
      expect(result).not_to have_key(:execution_mode)
      expect(result).not_to have_key(:retrieval_skipped)
      expect(result).not_to have_key(:memory_skipped)
    end
  end
end
