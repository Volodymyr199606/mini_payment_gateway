# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Skills::InvocationCoordinator do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }
  let(:customer) { merchant.customers.create!(email: "coord_#{SecureRandom.hex(4)}@example.com") }

  describe '.post_tool' do
    it 'invokes payment_state_explainer when operational has payment intent data' do
      pi = merchant.payment_intents.create!(customer: customer, amount_cents: 1000, currency: 'USD', status: 'captured')
      run_result = Ai::Orchestration::RunResult.new(
        orchestration_used: true,
        step_count: 1,
        tool_names: ['get_payment_intent'],
        deterministic_data: { id: pi.id, status: 'captured', amount_cents: 1000, currency: 'USD' },
        success: true,
        reply_text: 'Raw'
      )
      outcome = described_class.post_tool(
        agent_key: :operational,
        merchant_id: merchant.id,
        message: 'status',
        tool_names: ['get_payment_intent'],
        deterministic_data: run_result.deterministic_data,
        run_result: run_result
      )
      expect(outcome[:invocation_results].size).to eq(1)
      expect(outcome[:invocation_results].first[:skill_key]).to eq('payment_state_explainer')
      expect(outcome[:invocation_results].first[:invoked]).to be true
      expect(outcome[:skill_affected_reply]).to be true
      expect(outcome[:reply_text]).to include('captured')
    end

    it 'returns original reply when no skill invoked' do
      run_result = Ai::Orchestration::RunResult.new(
        orchestration_used: true,
        step_count: 1,
        tool_names: ['get_merchant_account'],
        deterministic_data: { id: 1 },
        success: true,
        reply_text: 'Original reply'
      )
      outcome = described_class.post_tool(
        agent_key: :developer_onboarding,
        merchant_id: merchant.id,
        message: 'account',
        tool_names: ['get_merchant_account'],
        deterministic_data: run_result.deterministic_data,
        run_result: run_result
      )
      expect(outcome[:invocation_results]).to be_empty
      expect(outcome[:reply_text]).to eq('Original reply')
    end
  end

  describe '.try_pre_composition_rewrite' do
    it 'returns rewritten text for concise_rewrite with prior content' do
      plan = Ai::Performance::ExecutionPlan.new(
        execution_mode: :concise_rewrite_only,
        skip_retrieval: false,
        skip_memory: false,
        skip_orchestration: true,
        retrieval_budget_reduced: true,
        reason_codes: ['concise_rewrite'],
        metadata: {}
      )
      result = described_class.try_pre_composition_rewrite(
        agent_key: :support_faq,
        merchant_id: merchant.id,
        message: 'bullet points',
        followup: { followup_type: :explanation_rewrite, response_style_adjustments: [:bullet_points] },
        prior_assistant_content: 'First point. Second point.',
        execution_plan: plan
      )
      expect(result).to be_present
      expect(result[:reply_text]).to include('•')
      expect(result[:invocation_results].first[:skill_key]).to eq('followup_rewriter')
    end

    it 'returns nil when not concise_rewrite mode' do
      plan = Ai::Performance::ExecutionPlan.new(
        execution_mode: :agent_full,
        skip_retrieval: false,
        skip_memory: false,
        skip_orchestration: true,
        retrieval_budget_reduced: false,
        reason_codes: [],
        metadata: {}
      )
      result = described_class.try_pre_composition_rewrite(
        agent_key: :support_faq,
        merchant_id: merchant.id,
        message: 'simpler',
        followup: { followup_type: :explanation_rewrite },
        prior_assistant_content: 'Text.',
        execution_plan: plan
      )
      expect(result).to be_nil
    end
  end
end
