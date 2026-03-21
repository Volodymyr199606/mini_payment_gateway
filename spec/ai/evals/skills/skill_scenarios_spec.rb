# frozen_string_literal: true

require 'rails_helper'

# Skill-specific scenario evals: validate correct skill invocation and impact.
RSpec.describe 'AI skill scenarios', type: :eval do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }
  let(:fixture_path) { Rails.root.join('spec/fixtures/ai/skill_scenarios.yml') }
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

  it 'runs all skill scenarios and every scenario passes' do
    skip 'fixture missing' unless fixture_path.exist?

    results = Ai::Evals::Skills::SkillScenarioRunner.run_all(
      merchant_id: merchant.id,
      path: fixture_path,
      entity_factory: entity_factory
    )

    failed = results.reject { |r| r[:passed_overall] }
    expect(failed).to eq([]), failure_message(failed)
  end

  describe 'individual skill coverage' do
    it 'payment_state_explainer is invoked for payment intent and affects response' do
      scenario = find_skill_scenario('skill-pi-explainer')
      ids = entity_factory.call(scenario, merchant.id)
      result = Ai::Evals::Skills::SkillScenarioRunner.run_one(
        scenario,
        merchant_id: merchant.id,
        entity_ids: ids
      )
      expect(result[:passed_overall]).to be(true), result[:failure_summary]
      expect(result[:skill_outcome][:invocation_results].map { |r| r[:skill_key] }).to include('payment_state_explainer')
      expect(result[:skill_outcome][:skill_affected_reply]).to be(true)
    end

    it 'webhook_trace_explainer is invoked for webhook event lookup' do
      scenario = find_skill_scenario('skill-webhook-explainer')
      ids = entity_factory.call(scenario, merchant.id)
      result = Ai::Evals::Skills::SkillScenarioRunner.run_one(
        scenario,
        merchant_id: merchant.id,
        entity_ids: ids
      )
      expect(result[:passed_overall]).to be(true), result[:failure_summary]
      expect(result[:skill_outcome][:invocation_results].map { |r| r[:skill_key] }).to include('webhook_trace_explainer')
    end

    it 'ledger_period_summary is invoked for ledger summary requests' do
      scenario = find_skill_scenario('skill-ledger-summary')
      result = Ai::Evals::Skills::SkillScenarioRunner.run_one(
        scenario,
        merchant_id: merchant.id,
        entity_ids: {}
      )
      expect(result[:passed_overall]).to be(true), result[:failure_summary]
      expect(result[:skill_outcome][:invocation_results].map { |r| r[:skill_key] }).to include('ledger_period_summary')
    end

    it 'no skill is invoked for get_merchant_account' do
      scenario = find_skill_scenario('skill-no-skill-account')
      result = Ai::Evals::Skills::SkillScenarioRunner.run_one(
        scenario,
        merchant_id: merchant.id,
        entity_ids: {}
      )
      expect(result[:passed_overall]).to be(true), result[:failure_summary]
      expect(result[:skill_outcome][:invocation_results]).to be_empty
    end
  end

  private

  def find_skill_scenario(id)
    Ai::Evals::Skills::SkillScenarioRunner.load_scenarios(fixture_path).find { |s| s[:id] == id }
  end

  def failure_message(failed)
    lines = failed.map { |r| "[#{r[:scenario_id]}] #{r[:failure_summary] || r[:error]}" }
    "Skill scenario failures:\n#{lines.join("\n")}"
  end
end
