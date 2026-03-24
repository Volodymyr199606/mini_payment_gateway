# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Skill regression scenarios', type: :eval do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }
  let(:fixture_path) { Rails.root.join('spec/fixtures/ai/skill_regression_scenarios.yml') }
  let(:entity_factory) { ->(scenario, merchant_id) { Ai::ScenarioEntityFactory.call(scenario, merchant_id) } }

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

  it 'runs all skill regression scenarios' do
    skip 'fixture missing' unless fixture_path.exist?

    results = Ai::Evals::Skills::SkillRegressionRunner.run_all(
      merchant_id: merchant.id,
      path: fixture_path,
      entity_factory: entity_factory
    )

    failed = results.reject { |r| r[:passed_overall] }
    expect(failed).to eq([]), failure_message(failed)
  end

  it 'discovers scenarios via SkillRegressionRunner.load_scenarios' do
    list = Ai::Evals::Skills::SkillRegressionRunner.load_scenarios(fixture_path)
    expect(list.map { |s| s[:id] }).to include('reg-support-pi-explainer', 'reg-no-skill-account')
  end

  private

  def failure_message(failed)
    lines = failed.map { |r| "[#{r[:scenario_id]}] #{r[:failure_summary] || r[:error]}" }
    "Skill regression failures:\n#{lines.join("\n")}"
  end
end
