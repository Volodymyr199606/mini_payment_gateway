# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Skills::ValueAnalysis::MetricCalculator do
  def skill_hash(skill_key, invoked: true, affected: true, deterministic: true, agent_key: 'operational')
    {
      'skill_key' => skill_key,
      'invoked' => invoked,
      'affected_final_response' => affected,
      'deterministic' => deterministic,
      'agent_key' => agent_key,
      'success' => true
    }
  end

  it 'returns empty-shaped metrics when no audits' do
    AiRequestAudit.delete_all
    m = described_class.call(scope: AiRequestAudit.all)
    expect(m[:audit_sample_size]).to eq(0)
    expect(m[:by_skill]).to eq({})
  end

  it 'aggregates per-skill rates and workflow keys' do
    AiRequestAudit.delete_all
    AiRequestAudit.create!(
      request_id: 'v1',
      endpoint: 'dashboard',
      agent_key: 'operational',
      merchant_id: nil,
      success: true,
      invoked_skills: [skill_hash('payment_state_explainer')],
      skill_workflow_metadata: { 'workflow_key' => 'payment_explain_with_docs' },
      deterministic_explanation_used: true,
      fallback_used: false,
      tool_used: true
    )
    AiRequestAudit.create!(
      request_id: 'v2',
      endpoint: 'dashboard',
      agent_key: 'operational',
      merchant_id: nil,
      success: true,
      invoked_skills: [skill_hash('payment_state_explainer', affected: false)],
      skill_workflow_metadata: {},
      deterministic_explanation_used: false,
      fallback_used: false,
      tool_used: true
    )

    m = described_class.call(scope: AiRequestAudit.all)
    expect(m[:audit_sample_size]).to eq(2)
    expect(m[:requests_with_any_skill]).to eq(2)
    expect(m[:workflow_key_frequency]['payment_explain_with_docs']).to eq(1)
    expect(m[:workflow_breakdown]['payment_explain_with_docs'][:audit_count]).to eq(1)
    expect(m[:workflow_selection_rate]).to eq(0.5)
    pi = m[:by_skill]['payment_state_explainer']
    expect(pi[:invocation_count]).to eq(2)
    expect(pi[:affected_rate]).to eq(0.5)
    expect(pi[:deterministic_rate]).to eq(1.0)
    expect(m[:skill_invocations_by_audit_agent]['operational']['payment_state_explainer']).to eq(2)
    expect(m[:skill_helpfulness_proxy][:request_affected_rate]).to eq(0.5)
    expect(m[:deterministic_path_strengthened_requests]).to eq(1)
  end
end
