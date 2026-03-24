# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Skills::InvocationContext do
  describe '.for_post_tool' do
    it 'detects payment data from tool_names' do
      ctx = described_class.for_post_tool(
        agent_key: :operational,
        merchant_id: 1,
        message: 'status',
        tool_names: ['get_payment_intent'],
        deterministic_data: { id: 1, status: 'created' }
      )
      expect(ctx.has_payment_data?).to be true
      expect(ctx.has_webhook_data?).to be false
      expect(ctx.has_ledger_data?).to be false
    end

    it 'detects webhook data from tool_names' do
      ctx = described_class.for_post_tool(
        agent_key: :operational,
        merchant_id: 1,
        message: 'webhook',
        tool_names: ['get_webhook_event'],
        deterministic_data: { id: 1 }
      )
      expect(ctx.has_webhook_data?).to be true
    end

    it 'has_webhook_retry_relevant_state? true when pending or failed' do
      ctx_pending = described_class.for_post_tool(
        agent_key: :operational,
        merchant_id: 1,
        message: 'webhook',
        tool_names: ['get_webhook_event'],
        deterministic_data: { id: 1, delivery_status: 'pending', attempts: 1 }
      )
      expect(ctx_pending.has_webhook_retry_relevant_state?).to be true

      ctx_failed = described_class.for_post_tool(
        agent_key: :operational,
        merchant_id: 1,
        message: 'webhook',
        tool_names: ['get_webhook_event'],
        deterministic_data: { id: 1, delivery_status: 'failed', attempts: 3 }
      )
      expect(ctx_failed.has_webhook_retry_relevant_state?).to be true
    end

    it 'has_webhook_retry_relevant_state? false when succeeded' do
      ctx = described_class.for_post_tool(
        agent_key: :operational,
        merchant_id: 1,
        message: 'webhook',
        tool_names: ['get_webhook_event'],
        deterministic_data: { id: 1, delivery_status: 'succeeded', attempts: 1 }
      )
      expect(ctx.has_webhook_retry_relevant_state?).to be false
    end

    it 'has_trend_context? matches trend/compare/previous keywords' do
      ctx = described_class.for_post_tool(
        agent_key: :reporting_calculation,
        merchant_id: 1,
        message: 'compare charges this week vs last week',
        tool_names: ['get_ledger_summary'],
        deterministic_data: {}
      )
      expect(ctx.has_trend_context?).to be true
    end

    it 'detects ledger data from tool_names' do
      ctx = described_class.for_post_tool(
        agent_key: :reporting_calculation,
        merchant_id: 1,
        message: 'ledger',
        tool_names: ['get_ledger_summary'],
        deterministic_data: { totals: {} }
      )
      expect(ctx.has_ledger_data?).to be true
    end

    it 'builds skill context with entity data for post_tool' do
      ctx = described_class.for_post_tool(
        agent_key: :operational,
        merchant_id: 1,
        message: 'status',
        tool_names: ['get_payment_intent'],
        deterministic_data: { id: 42, status: 'captured', amount_cents: 1000 }
      )
      skill_ctx = ctx.to_skill_context
      expect(skill_ctx[:merchant_id]).to eq(1)
      expect(skill_ctx[:payment_intent]).to be_present
      expect(skill_ctx[:payment_intent][:id]).to eq(42)
    end
  end

  describe '.for_pre_composition' do
    it 'exposes followup_rewrite? and concise_rewrite_mode?' do
      plan = Struct.new(:execution_mode).new(:concise_rewrite_only)
      ctx = described_class.for_pre_composition(
        agent_key: :support_faq,
        merchant_id: 1,
        message: 'simpler',
        followup: { followup_type: :explanation_rewrite },
        prior_assistant_content: 'Some text.',
        execution_plan: plan
      )
      expect(ctx.followup_rewrite?).to be true
      expect(ctx.concise_rewrite_mode?).to be true
    end
  end
end
