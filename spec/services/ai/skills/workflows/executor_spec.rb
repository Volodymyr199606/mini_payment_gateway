# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Skills::Workflows::Executor do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }

  before do
    allow(Ai::Observability::EventLogger).to receive(:log_skill_invocation)
  end

  describe '.run_post_tool' do
    it 'runs reconciliation workflow with two skills and returns workflow_result' do
      wf = Ai::Skills::Workflows::Registry.fetch(:reconciliation_analysis_workflow)
      pi = merchant.payment_intents.create!(
        customer: merchant.customers.create!(email: "c_#{SecureRandom.hex(4)}@x.com"),
        amount_cents: 1000,
        currency: 'USD',
        status: 'captured'
      )
      ledger_stub = {
        currency: 'USD',
        from: '2025-01-01T00:00:00Z',
        to: '2025-01-08T23:59:59Z',
        totals: { charges_cents: 100_00, refunds_cents: 20_00, fees_cents: 5_00, net_cents: 80_00 },
        counts: { captures_count: 10, refunds_count: 2 }
      }
      allow(Reporting::LedgerSummary).to receive(:new).and_return(
        instance_double(Reporting::LedgerSummary, call: ledger_stub)
      )

      run_result = Ai::Orchestration::RunResult.new(
        orchestration_used: false,
        step_count: 1,
        tool_names: ['get_ledger_summary'],
        deterministic_data: { ledger_summary: ledger_stub, payment_intent: { id: pi.id } },
        success: true,
        reply_text: 'Ledger raw'
      )
      context = Ai::Skills::InvocationContext.for_post_tool(
        agent_key: :reconciliation_analyst,
        merchant_id: merchant.id,
        message: 'reconcile',
        tool_names: ['get_ledger_summary'],
        deterministic_data: run_result.deterministic_data,
        run_result: run_result
      )

      out = described_class.run_post_tool(
        workflow_def: wf,
        context: context,
        run_result: run_result,
        routing_agent_key: :reconciliation_analyst
      )

      expect(out[:workflow_result]).to be_a(Ai::Skills::Workflows::WorkflowResult)
      expect(out[:workflow_result].workflow_key).to eq('reconciliation_analysis_workflow')
      expect(out[:invocation_results].size).to eq(2)
      expect(out[:workflow_result].steps_completed).to eq(2)
    end

    it 'rejects nested workflow execution' do
      wf = Ai::Skills::Workflows::Registry.fetch(:reconciliation_analysis_workflow)
      Thread.current[:ai_workflow_executing] = true
      expect do
        described_class.run_post_tool(
          workflow_def: wf,
          context: instance_double(Ai::Skills::InvocationContext, phase: :post_tool),
          run_result: instance_double(Ai::Orchestration::RunResult, reply_text: '', deterministic_data: {}, step_count: 1),
          routing_agent_key: :reconciliation_analyst
        )
      end.to raise_error(Ai::Skills::Workflows::NestedWorkflowError)
    ensure
      Thread.current[:ai_workflow_executing] = nil
    end
  end

  describe '.attach_rewrite_metadata' do
    it 'builds workflow result for rewrite path' do
      wr = described_class.attach_rewrite_metadata(
        invocation_results: [{ skill_key: 'followup_rewriter', invoked: true, success: true, phase: 'pre_composition' }],
        routing_agent_key: :support_faq
      )
      expect(wr.workflow_key).to eq('rewrite_response_workflow')
    end
  end
end
