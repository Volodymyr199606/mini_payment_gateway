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
