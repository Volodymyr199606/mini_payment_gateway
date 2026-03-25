# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Skills::ValueAnalysis::ReportBuilder do
  it 'builds structured report with stable top-level keys' do
    AiRequestAudit.delete_all
    r = described_class.build(audit_scope: AiRequestAudit.all)
    expect(r).to include(
      :generated_at, :metrics, :scenario_coverage, :scenario_scorecard_summary, :static, :rankings,
      :agent_summaries, :recommendations, :markdown
    )
    expect(r[:metrics][:audit_sample_size]).to eq(0)
    expect(r[:static]).to include(:registered_skill_keys, :registered_workflow_keys)
    expect(r[:rankings]).to include(:by_eval_scenario_coverage, :by_production_signal, :notes)
    expect(r[:agent_summaries]).to be_an(Array)
    expect(r[:agent_summaries].map { |a| a[:agent_key] }).to include('operational')
    expect(r[:recommendations]).to include(:keep_expand, :watch_or_validate, :prune_or_simplify)
  end

  it 'includes markdown sections and workflow keys from registry' do
    md = described_class.build(audit_scope: AiRequestAudit.all)[:markdown]
    expect(md).to include('AI skill value')
    expect(md).to include('## Audit sample')
    expect(md).to include('## Highest-value skills')
    expect(md).to include('## Agents — skill value')
    expect(md).to include('## Recommendations')
    expect(md).to include('## Deterministic paths strengthened')
    expect(md).to include('## Eval / regression coverage')
    expect(md).to match(/payment_explain_with_docs|reconciliation_analysis_workflow/)
  end

  it 'includes production metrics when audits exist' do
    AiRequestAudit.delete_all
    AiRequestAudit.create!(
      request_id: 'rb1',
      endpoint: 'dashboard',
      agent_key: 'reporting_calculation',
      merchant_id: nil,
      success: true,
      invoked_skills: [
        {
          'skill_key' => 'ledger_period_summary',
          'invoked' => true,
          'affected_final_response' => true,
          'deterministic' => true,
          'success' => true
        }
      ],
      skill_workflow_metadata: nil,
      deterministic_explanation_used: true,
      fallback_used: false,
      tool_used: true
    )
    r = described_class.build(audit_scope: AiRequestAudit.all)
    expect(r[:metrics][:audit_sample_size]).to eq(1)
    expect(r[:metrics][:by_skill]['ledger_period_summary']).to be_present
    expect(r[:markdown]).to include('ledger_period_summary')
  end
end
