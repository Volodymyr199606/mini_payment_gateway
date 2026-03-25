# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Skills::Workflows::Selector do
  let(:merchant_id) { 1 }

  def ctx(agent, tool_names, data, message: 'test')
    Ai::Skills::InvocationContext.for_post_tool(
      agent_key: agent,
      merchant_id: merchant_id,
      message: message,
      tool_names: tool_names,
      deterministic_data: data,
      run_result: nil
    )
  end

  describe '.select_post_tool' do
    it 'selects reconciliation workflow when routing analyst + ledger tool' do
      data = { ledger_summary: { from: 'a', to: 'b', totals: {} } }
      c = ctx(:reporting_calculation, ['get_ledger_summary'], data, message: 'reconciliation statement mismatch last 7 days')
      wf = described_class.select_post_tool(
        routing_agent_key: :reporting_calculation,
        skill_agent: :reporting_calculation,
        context: c
      )
      expect(wf&.key).to eq(:reconciliation_analysis_workflow)
    end

    it 'selects payment+docs when support_faq, payment data, and docs-like message' do
      data = { payment_intent: { id: 1, status: 'captured', amount_cents: 100, currency: 'USD' } }
      c = ctx(:operational, ['get_payment_intent'], data, message: 'What is the API fee policy for this payment?')
      wf = described_class.select_post_tool(
        routing_agent_key: :operational,
        skill_agent: :operational,
        context: c
      )
      expect(wf&.key).to eq(:payment_explain_with_docs)
    end

    it 'does not select payment workflow without docs-like message' do
      data = { payment_intent: { id: 1, status: 'captured', amount_cents: 100, currency: 'USD' } }
      c = ctx(:operational, ['get_payment_intent'], data, message: 'status only')
      wf = described_class.select_post_tool(
        routing_agent_key: :operational,
        skill_agent: :operational,
        context: c
      )
      expect(wf).to be_nil
    end

    it 'returns nil when workflows disabled' do
      old = ENV['AI_SKILL_WORKFLOWS_DISABLED']
      ENV['AI_SKILL_WORKFLOWS_DISABLED'] = '1'
      data = { ledger_summary: { totals: {} } }
      c = ctx(:reporting_calculation, ['get_ledger_summary'], data, message: 'reconciliation statement mismatch last 7 days')
      wf = described_class.select_post_tool(
        routing_agent_key: :reporting_calculation,
        skill_agent: :reporting_calculation,
        context: c
      )
      expect(wf).to be_nil
    ensure
      old.nil? ? ENV.delete('AI_SKILL_WORKFLOWS_DISABLED') : ENV['AI_SKILL_WORKFLOWS_DISABLED'] = old
    end
  end
end
