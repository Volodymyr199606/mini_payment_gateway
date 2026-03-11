# frozen_string_literal: true

require 'rails_helper'

# End-to-end AI scenario specs: validate full stack (orchestration, tools, routing, retrieval, composition).
# Uses spec/fixtures/ai/scenarios.yml. Groq and Reporting::LedgerSummary are stubbed.
RSpec.describe 'AI end-to-end scenarios', type: :eval do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }
  let(:fixture_path) { Rails.root.join('spec/fixtures/ai/scenarios.yml') }

  let(:entity_factory) do
    ->(scenario, merchant_id) { Ai::ScenarioEntityFactory.call(scenario, merchant_id) }
  end

  before do
    allow(Ai::Observability::EventLogger).to receive(:log_tool_call)
    allow(Ai::Observability::EventLogger).to receive(:log_orchestration_run)
    allow(WebhookDeliveryJob).to receive(:perform_later)
    Ai::Rag::DocsIndex.reset!
    Ai::Rag::ContextGraph.reset!

    groq_stub = instance_double(
      Ai::GroqClient,
      chat: { content: 'Stub reply for scenario eval.', model_used: 'scenario-stub', fallback_used: false }
    )
    allow(Ai::GroqClient).to receive(:new).and_return(groq_stub)

    streaming_stub = instance_double(
      Ai::Generation::StreamingClient,
      stream: { content: 'Stub reply for scenario eval.', error: nil }
    )
    allow(Ai::Generation::StreamingClient).to receive(:new).and_return(streaming_stub)

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

  it 'runs all scenarios and every scenario passes' do
    skip 'fixture missing' unless fixture_path.exist?

    results = Ai::Evals::ScenarioRunner.run_all(
      merchant_id: merchant.id,
      path: fixture_path,
      entity_factory: entity_factory
    )

    failed = results.reject { |r| r[:passed_overall] }
    expect(failed).to eq([]), failure_message(failed)
  end

  describe 'individual scenario coverage' do
    before do
      allow(Ai::Observability::EventLogger).to receive(:log_tool_call)
      allow(Ai::Observability::EventLogger).to receive(:log_orchestration_run)
      allow(WebhookDeliveryJob).to receive(:perform_later)
      Ai::Rag::DocsIndex.reset!
      Ai::Rag::ContextGraph.reset!
    end

    it 'tool-only account scenario passes' do
      scenario = find_scenario('scenario-tool-account')
      ids = entity_factory.call(scenario, merchant.id)
      result = Ai::Evals::ScenarioRunner.run_one(
        scenario,
        merchant_id: merchant.id,
        entity_ids: ids
      )
      expect(result[:passed_overall]).to be(true), result[:failure_summary]
      expect(result[:path]).to eq('tool_only')
      expect(result[:agent_key]).to eq('tool:get_merchant_account')
    end

    it 'docs-only refunds scenario passes' do
      scenario = find_scenario('scenario-docs-refunds')
      result = Ai::Evals::ScenarioRunner.run_one(
        scenario,
        merchant_id: merchant.id,
        entity_ids: {}
      )
      expect(result[:passed_overall]).to be(true), result[:failure_summary]
      expect(result[:agent_key]).to eq('operational')
      expect(result[:citations_count]).to be >= 1
    end

    it 'orchestration scenario (transaction -> payment intent) passes' do
      scenario = find_scenario('scenario-orchestration-txn-pi')
      ids = entity_factory.call(scenario, merchant.id)
      result = Ai::Evals::ScenarioRunner.run_one(
        scenario,
        merchant_id: merchant.id,
        entity_ids: ids
      )
      expect(result[:passed_overall]).to be(true), result[:failure_summary]
      expect(result[:path]).to eq('orchestration')
      expect(result[:agent_key]).to eq('orchestration')
      expect(result[:tool_names]).to eq(%w[get_transaction get_payment_intent])
    end
  end

  private

  def find_scenario(id)
    Ai::Evals::ScenarioRunner.load_scenarios(fixture_path).find { |s| s[:id] == id }
  end

  def failure_message(failed)
    lines = failed.map do |r|
      "[#{r[:scenario_id]}] #{r[:failure_summary] || r[:error]}: #{r[:user_message].to_s[0, 60]}..."
    end
    "Scenario failures:\n#{lines.join("\n")}"
  end
end
