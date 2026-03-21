# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Skills::InvocationPlanner do
  describe '.plan' do
    it 'returns nil when already_invoked reaches max' do
      ctx = Ai::Skills::InvocationContext.for_post_tool(
        agent_key: :operational,
        merchant_id: 1,
        message: 'status',
        tool_names: ['get_payment_intent'],
        deterministic_data: { id: 1, status: 'captured' }
      )
      planned = described_class.plan(context: ctx, already_invoked: [:payment_state_explainer, :webhook_trace_explainer])
      expect(planned).to be_nil
    end

    it 'plans payment_state_explainer when operational has payment data' do
      ctx = Ai::Skills::InvocationContext.for_post_tool(
        agent_key: :operational,
        merchant_id: 1,
        message: 'status',
        tool_names: ['get_payment_intent'],
        deterministic_data: { id: 1, status: 'captured' }
      )
      planned = described_class.plan(context: ctx, already_invoked: [])
      expect(planned[:skill_key]).to eq(:payment_state_explainer)
      expect(planned[:reason_code]).to eq('payment_data_retrieved')
    end

    it 'does not plan payment_state_explainer when agent does not allow it' do
      ctx = Ai::Skills::InvocationContext.for_post_tool(
        agent_key: :developer_onboarding,
        merchant_id: 1,
        message: 'status',
        tool_names: ['get_payment_intent'],
        deterministic_data: { id: 1 }
      )
      planned = described_class.plan(context: ctx, already_invoked: [])
      expect(planned).to be_nil
    end

    it 'plans webhook_trace_explainer when operational has webhook data' do
      ctx = Ai::Skills::InvocationContext.for_post_tool(
        agent_key: :operational,
        merchant_id: 1,
        message: 'webhook status',
        tool_names: ['get_webhook_event'],
        deterministic_data: { id: 1, delivery_status: 'succeeded' }
      )
      planned = described_class.plan(context: ctx, already_invoked: [])
      expect(planned[:skill_key]).to eq(:webhook_trace_explainer)
      expect(planned[:reason_code]).to eq('webhook_data_retrieved')
    end

    it 'plans ledger_period_summary when reporting has ledger data' do
      ctx = Ai::Skills::InvocationContext.for_post_tool(
        agent_key: :reporting_calculation,
        merchant_id: 1,
        message: 'last 7 days',
        tool_names: ['get_ledger_summary'],
        deterministic_data: { totals: {}, from: '2025-01-01', to: '2025-01-07' }
      )
      planned = described_class.plan(context: ctx, already_invoked: [])
      expect(planned[:skill_key]).to eq(:ledger_period_summary)
      expect(planned[:reason_code]).to eq('ledger_data_retrieved')
    end

    it 'plans followup_rewriter for pre_composition when concise_rewrite' do
      ctx = Ai::Skills::InvocationContext.for_pre_composition(
        agent_key: :support_faq,
        merchant_id: 1,
        message: 'make that simpler',
        followup: { followup_type: :explanation_rewrite, response_style_adjustments: [:simpler] },
        prior_assistant_content: 'Payment Intent #1 is captured. Amount: $10.00.',
        execution_plan: Struct.new(:execution_mode).new(:concise_rewrite_only)
      )
      planned = described_class.plan(context: ctx, already_invoked: [])
      expect(planned[:skill_key]).to eq(:followup_rewriter)
      expect(planned[:reason_code]).to eq('concise_rewrite_with_prior')
    end

    it 'does not plan followup_rewriter without prior content' do
      ctx = Ai::Skills::InvocationContext.for_pre_composition(
        agent_key: :support_faq,
        merchant_id: 1,
        message: 'simpler',
        followup: { followup_type: :explanation_rewrite },
        prior_assistant_content: '',
        execution_plan: Struct.new(:execution_mode).new(:concise_rewrite_only)
      )
      planned = described_class.plan(context: ctx, already_invoked: [])
      expect(planned).to be_nil
    end
  end
end
