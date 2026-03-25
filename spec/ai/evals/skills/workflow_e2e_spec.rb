# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Bounded workflow end-to-end (skill layer)', type: :eval do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }

  before do
    allow(Ai::Observability::EventLogger).to receive(:log_tool_call)
    allow(Ai::Observability::EventLogger).to receive(:log_orchestration_run)
    allow(Ai::Observability::EventLogger).to receive(:log_skill_invocation)
    allow(WebhookDeliveryJob).to receive(:perform_later)
    Ai::Rag::DocsIndex.reset!
    Ai::Rag::ContextGraph.reset!

    groq_stub = instance_double(
      Ai::GroqClient,
      chat: { content: 'Stub reply.', model_used: 'stub', fallback_used: false }
    )
    allow(Ai::GroqClient).to receive(:new).and_return(groq_stub)
    allow(Ai::Generation::StreamingClient).to receive(:new).and_return(
      instance_double(Ai::Generation::StreamingClient, stream: { content: 'Stub reply.', error: nil })
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
  end

  def run_scenario(scenario, entity_ids: {})
    Ai::Evals::ScenarioRunner.run_one(scenario, merchant_id: merchant.id, entity_ids: entity_ids)
  end

  it 'payment_explain_with_docs workflow executes payment_state_explainer only' do
    pi = merchant.payment_intents.create!(
      customer: merchant.customers.create!(email: "c_pi_#{SecureRandom.hex(4)}@x.com"),
      amount_cents: 1000,
      currency: 'USD',
      status: 'captured'
    )

    scenario = {
      id: 'workflow-payment-explain-docs',
      user_message: 'What is the fee policy for payment intent {{payment_intent_id}}?',
      entity_refs: ['payment_intent'],
      expected_path: 'tool_only',
      expected_agent: 'tool:get_payment_intent',
      expected_tool_names: %w[get_payment_intent],
      expected_skill_keys: %w[payment_state_explainer],
      expected_skill_affected_response: true,
      expected_response_must_include: [],
      expected_response_must_not_include: [],
      require_citations: false
    }

    result = run_scenario(scenario, entity_ids: { payment_intent_id: pi.id })
    workflow = result.dig(:skill_outcome, :workflow_result)
    expect(workflow&.workflow_key).to eq('payment_explain_with_docs')
    expect(workflow&.steps_completed).to eq(1)
    expect(workflow&.skipped_skills).to be_blank
  end

  it 'reconciliation_analysis_workflow fills supporting_analysis and next_steps' do
    scenario = {
      id: 'workflow-reconciliation-analysis',
      user_message: 'reconciliation discrepancy mismatch: what is my net volume for the last 7 days?',
      entity_refs: [],
      expected_path: 'tool_only',
      expected_agent: 'tool:get_ledger_summary',
      expected_tool_names: %w[get_ledger_summary],
      expected_skill_keys: %w[discrepancy_detector reconciliation_action_summary],
      expected_skill_affected_response: true,
      expected_response_must_include: [],
      expected_response_must_not_include: [],
      require_citations: false
    }

    result = run_scenario(scenario)
    workflow = result.dig(:skill_outcome, :workflow_result)
    expect(workflow&.workflow_key).to eq('reconciliation_analysis_workflow')
    expect(workflow&.steps_completed).to eq(2)

    composition = result.dig(:skill_outcome, :composition_result)
    filled_slots = composition&.filled_slots
    expect(filled_slots.keys).to include('supporting_analysis', 'next_steps')
  end

  it 'webhook_failure_analysis_workflow skips payment_failure_summary when payment context is missing' do
    webhook_event = merchant.webhook_events.create!(
      event_type: 'payment_intent.captured',
      payload: { 'id' => 'evt_e2e_1', 'type' => 'payment_intent.captured' },
      delivery_status: 'pending',
      attempts: 1
    )

    scenario = {
      id: 'workflow-webhook-failure-analysis',
      user_message: 'What happened to webhook event {{webhook_event_id}}?',
      entity_refs: ['webhook_event'],
      expected_path: 'tool_only',
      expected_agent: 'tool:get_webhook_event',
      expected_tool_names: %w[get_webhook_event],
      expected_skill_keys: %w[webhook_trace_explainer],
      expected_skill_affected_response: true,
      expected_response_must_include: [],
      expected_response_must_not_include: [],
      require_citations: false
    }

    result = run_scenario(scenario, entity_ids: { webhook_event_id: webhook_event.id })
    workflow = result.dig(:skill_outcome, :workflow_result)
    expect(workflow&.workflow_key).to eq('webhook_failure_analysis_workflow')
    expect(workflow&.steps_completed).to eq(1)
    expect(workflow&.skipped_skills).to include('payment_failure_summary')
  end
end

