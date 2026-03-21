# frozen_string_literal: true

require 'rails_helper'

# Verifies skills are invoked only when appropriate (planner rules, agent allowlist, phase).
RSpec.describe 'AI skill invocation correctness', type: :eval do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }

  describe 'InvocationPlanner' do
    it 'plans payment_state_explainer when post_tool and has payment data' do
      ctx = Ai::Skills::InvocationContext.for_post_tool(
        agent_key: :operational,
        merchant_id: merchant.id,
        message: 'status of payment intent',
        tool_names: ['get_payment_intent'],
        deterministic_data: { payment_intent: { id: 1, status: 'captured' } },
        run_result: nil
      )
      planned = Ai::Skills::InvocationPlanner.plan(context: ctx, already_invoked: [])
      expect(planned[:skill_key]).to eq(:payment_state_explainer)
      expect(planned[:reason_code]).to eq('payment_data_retrieved')
    end

    it 'plans webhook_trace_explainer when post_tool and has webhook data' do
      ctx = Ai::Skills::InvocationContext.for_post_tool(
        agent_key: :operational,
        merchant_id: merchant.id,
        message: 'webhook event',
        tool_names: ['get_webhook_event'],
        deterministic_data: { webhook_event: { id: 1 } },
        run_result: nil
      )
      planned = Ai::Skills::InvocationPlanner.plan(context: ctx, already_invoked: [])
      expect(planned[:skill_key]).to eq(:webhook_trace_explainer)
      expect(planned[:reason_code]).to eq('webhook_data_retrieved')
    end

    it 'plans ledger_period_summary when post_tool and has ledger data' do
      ctx = Ai::Skills::InvocationContext.for_post_tool(
        agent_key: :reporting_calculation,
        merchant_id: merchant.id,
        message: 'totals',
        tool_names: ['get_ledger_summary'],
        deterministic_data: { ledger_summary: {} },
        run_result: nil
      )
      planned = Ai::Skills::InvocationPlanner.plan(context: ctx, already_invoked: [])
      expect(planned[:skill_key]).to eq(:ledger_period_summary)
      expect(planned[:reason_code]).to eq('ledger_data_retrieved')
    end

    it 'returns nil when agent does not allow the skill' do
      ctx = Ai::Skills::InvocationContext.for_post_tool(
        agent_key: :developer_onboarding,
        merchant_id: merchant.id,
        message: 'status',
        tool_names: ['get_payment_intent'],
        deterministic_data: { payment_intent: { id: 1 } },
        run_result: nil
      )
      planned = Ai::Skills::InvocationPlanner.plan(context: ctx, already_invoked: [])
      expect(planned).to be_nil
    end

    it 'returns nil when no payment/webhook/ledger data' do
      ctx = Ai::Skills::InvocationContext.for_post_tool(
        agent_key: :operational,
        merchant_id: merchant.id,
        message: 'account',
        tool_names: ['get_merchant_account'],
        deterministic_data: { id: 1 },
        run_result: nil
      )
      planned = Ai::Skills::InvocationPlanner.plan(context: ctx, already_invoked: [])
      expect(planned).to be_nil
    end

    it 'respects MAX_INVOCATIONS_PER_REQUEST' do
      ctx = Ai::Skills::InvocationContext.for_post_tool(
        agent_key: :operational,
        merchant_id: merchant.id,
        message: 'status',
        tool_names: ['get_payment_intent'],
        deterministic_data: { payment_intent: { id: 1 } },
        run_result: nil
      )
      planned = Ai::Skills::InvocationPlanner.plan(context: ctx, already_invoked: [:payment_state_explainer, :other])
      expect(planned).to be_nil
    end

    it 'plans followup_rewriter only for pre_composition with concise_rewrite and prior content' do
      plan = Ai::Performance::ExecutionPlan.new(
        execution_mode: :concise_rewrite_only,
        skip_retrieval: false,
        skip_memory: false,
        skip_orchestration: true,
        retrieval_budget_reduced: true,
        reason_codes: ['concise_rewrite'],
        metadata: {}
      )
      ctx = Ai::Skills::InvocationContext.for_pre_composition(
        agent_key: :support_faq,
        merchant_id: merchant.id,
        message: 'bullet points',
        followup: { followup_type: :explanation_rewrite, response_style_adjustments: [:bullet_points] },
        prior_assistant_content: 'Some prior reply.',
        execution_plan: plan
      )
      planned = Ai::Skills::InvocationPlanner.plan(context: ctx, already_invoked: [])
      expect(planned[:skill_key]).to eq(:followup_rewriter)
      expect(planned[:reason_code]).to eq('concise_rewrite_with_prior')
    end

    it 'returns nil for followup_rewriter when prior content blank' do
      plan = Ai::Performance::ExecutionPlan.new(
        execution_mode: :concise_rewrite_only,
        skip_retrieval: false,
        skip_memory: false,
        skip_orchestration: true,
        retrieval_budget_reduced: true,
        reason_codes: [],
        metadata: {}
      )
      ctx = Ai::Skills::InvocationContext.for_pre_composition(
        agent_key: :support_faq,
        merchant_id: merchant.id,
        message: 'simpler',
        followup: { followup_type: :explanation_rewrite },
        prior_assistant_content: '',
        execution_plan: plan
      )
      planned = Ai::Skills::InvocationPlanner.plan(context: ctx, already_invoked: [])
      expect(planned).to be_nil
    end
  end
end
