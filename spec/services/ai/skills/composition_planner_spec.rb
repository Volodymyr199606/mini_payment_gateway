# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Skills::CompositionPlanner do
  describe '.plan' do
    it 'merges single skill explanation as reply' do
      results = [
        {
          skill_key: 'payment_state_explainer',
          invoked: true,
          success: true,
          deterministic: true,
          explanation: 'PI is captured.'
        }
      ]
      r = described_class.plan(reply_text: 'Tool raw', invocation_results: results, agent_key: :operational)
      expect(r.reply_text).to eq('PI is captured.')
      expect(r.contributing_skills).to include('payment_state_explainer')
    end

    it 'keeps tool reply when no successful invocation' do
      r = described_class.plan(reply_text: 'Only tool', invocation_results: [], agent_key: :operational)
      expect(r.reply_text).to eq('Only tool')
      expect(r.contributing_skills).to be_empty
    end

    it 'preserves combined orchestration reply when multiple tools ran (does not replace with single skill)' do
      combined = "Transaction #1 succeeded.\n\nPayment Intent #2 is **created**."
      results = [
        {
          skill_key: 'payment_state_explainer',
          invoked: true,
          success: true,
          deterministic: true,
          explanation: 'Payment Intent #2 is in **created** status.'
        }
      ]
      r = described_class.plan(
        reply_text: combined,
        invocation_results: results,
        agent_key: :operational,
        tool_names: %w[get_transaction get_payment_intent]
      )
      expect(r.reply_text).to eq(combined)
      expect(r.composition_mode).to eq('multi_step_tool_reply_preserved')
    end

    it 'preserves combined reply when step_count > 1 even if tool_names lists only one tool' do
      combined = "Transaction #1 succeeded.\n\nPayment Intent #2 is **created**."
      results = [
        {
          skill_key: 'payment_state_explainer',
          invoked: true,
          success: true,
          deterministic: true,
          explanation: 'Payment Intent #2 is in **created** status.'
        }
      ]
      r = described_class.plan(
        reply_text: combined,
        invocation_results: results,
        agent_key: :operational,
        tool_names: %w[get_payment_intent],
        orchestration_step_count: 2
      )
      expect(r.reply_text).to eq(combined)
      expect(r.composition_mode).to eq('multi_step_tool_reply_preserved')
    end

    it 'appends supporting analysis when slot is additive' do
      results = [
        {
          skill_key: 'discrepancy_detector',
          invoked: true,
          success: true,
          deterministic: true,
          explanation: 'Check: refunds exceed charges.'
        }
      ]
      r = described_class.plan(reply_text: 'Ledger net $10.', invocation_results: results, agent_key: :reconciliation_analyst)
      expect(r.reply_text).to include('Ledger net')
      expect(r.reply_text).to include('refunds exceed')
    end
  end
end
