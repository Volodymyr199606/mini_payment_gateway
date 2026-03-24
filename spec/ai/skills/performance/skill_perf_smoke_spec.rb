# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Skill performance smoke', type: :eval do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }

  it 'InvocationPlanner.plan_all_for_request stays within global and profile caps' do
    ctx = Ai::Skills::InvocationContext.for_post_tool(
      agent_key: :reconciliation_analyst,
      merchant_id: merchant.id,
      message: 'reconcile',
      tool_names: ['get_ledger_summary'],
      deterministic_data: { ledger_summary: {}, payment_intent: { id: 1 } },
      run_result: nil
    )
    planned = Ai::Skills::InvocationPlanner.plan_all_for_request(context: ctx, phase: :post_tool)
    profile = Ai::Skills::AgentProfiles.for(:reconciliation_analyst)
    cap = [profile.max_skills_per_request, Ai::Skills::InvocationPlanner::MAX_INVOCATIONS_PER_REQUEST].min
    expect(planned.size).to be <= cap
  end

  it 'MetricSamples.percentile is deterministic for fixed input' do
    s = [10.0, 20.0, 30.0, 40.0, 50.0]
    expect(Ai::Evals::Skills::MetricSamples.median(s)).to eq(30.0)
  end

  it 'PerfComparison.median_ratio_within? compares relative medians' do
    a = [1.0, 1.0, 1.0]
    b = [2.0, 2.0, 2.0]
    expect(Ai::Evals::Skills::PerfComparison.median_ratio_within?(a, b, max_ratio: 3.0)).to be(true)
    expect(Ai::Evals::Skills::PerfComparison.median_ratio_within?(a, b, max_ratio: 1.5)).to be(false)
  end

  describe 'local median ratio gate', :perf_local do
    before do
      skip 'Set RUN_PERF_LOCAL=1 to run wall-clock median ratio checks' unless ENV['RUN_PERF_LOCAL'] == '1'
    end

    it 'ledger scenario median wall time stays within baseline ratio vs account scenario' do
      allow(Ai::Observability::EventLogger).to receive(:log_tool_call)
      allow(Ai::Observability::EventLogger).to receive(:log_orchestration_run)
      allow(Ai::Observability::EventLogger).to receive(:log_skill_invocation)
      allow(WebhookDeliveryJob).to receive(:perform_later)
      Ai::Rag::DocsIndex.reset!
      Ai::Rag::ContextGraph.reset!
      allow(Ai::GroqClient).to receive(:new).and_return(
        instance_double(Ai::GroqClient, chat: { content: 'Stub.', model_used: 'stub', fallback_used: false })
      )
      allow(Ai::Generation::StreamingClient).to receive(:new).and_return(
        instance_double(Ai::Generation::StreamingClient, stream: { content: 'Stub.', error: nil })
      )
      allow(Reporting::LedgerSummary).to receive(:new).and_return(
        instance_double(Reporting::LedgerSummary, call: { totals: {}, counts: {} })
      )

      m = create_merchant_with_api_key.first
      path = Rails.root.join('spec/fixtures/ai/skill_scenarios.yml')
      scenarios = Ai::Evals::ScenarioRunner.load_scenarios(path)
      a = scenarios.find { |s| s[:id] == 'skill-no-skill-account' }
      b = scenarios.find { |s| s[:id] == 'skill-ledger-summary' }
      baseline_path = Rails.root.join('spec/fixtures/ai/skill_perf_baselines.yml')
      cfg = YAML.load_file(baseline_path)['comparisons']['account_vs_ledger']
      iterations = cfg['iterations'].to_i

      samples_a = iterations.times.map do
        Ai::Evals::Skills::PerfComparison.time_block do
          Ai::Evals::ScenarioRunner.run_one(a, merchant_id: m.id, entity_ids: {})
        end[:wall_seconds]
      end
      samples_b = iterations.times.map do
        Ai::Evals::Skills::PerfComparison.time_block do
          Ai::Evals::ScenarioRunner.run_one(b, merchant_id: m.id, entity_ids: {})
        end[:wall_seconds]
      end

      ok = Ai::Evals::Skills::PerfComparison.median_ratio_within?(
        samples_a,
        samples_b,
        max_ratio: cfg['median_ratio_max'].to_f
      )
      report = Ai::Evals::Skills::PerfComparison.report_hash(
        label_a: 'account',
        samples_a: samples_a,
        label_b: 'ledger',
        samples_b: samples_b
      )
      path_written = Ai::Evals::Skills::GateReportWriter.write_json(name: 'perf_local_comparison', data: report)
      expect(ok).to be(true), "median ratio regression — see #{path_written}"
    end
  end
end
