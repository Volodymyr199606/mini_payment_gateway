# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Analytics::MetricsBuilder do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }

  describe '.call' do
    context 'when no audits' do
      it 'returns empty metrics' do
        rel = AiRequestAudit.where('1=0')
        m = described_class.call(rel)
        expect(m[:summary][:total_requests]).to eq(0)
        expect(m[:summary][:top_agent]).to be_nil
        expect(m[:recent_requests]).to eq([])
      end
    end

    context 'when audits exist' do
      before do
        create_audit(agent_key: 'operational', tool_used: true, tool_names: ['get_merchant_account'],
                     fallback_used: false, success: true, latency_ms: 100, composition_mode: 'tool_only')
        create_audit(agent_key: 'support_faq', tool_used: false, fallback_used: true,
                     success: true, latency_ms: 500, composition_mode: 'docs_only')
        create_audit(agent_key: 'operational', tool_used: false, authorization_denied: true,
                     success: false, followup_detected: true, followup_type: 'time_range_adjustment')
      end

      it 'aggregates summary correctly' do
        rel = AiRequestAudit.all
        m = described_class.call(rel)
        expect(m[:summary][:total_requests]).to eq(3)
        expect(m[:summary][:avg_latency_ms]).to eq(300) # (100+500)/2, nil excluded
        expect(m[:summary][:tool_usage_rate]).to be_within(0.01).of(1.0/3)
        expect(m[:summary][:fallback_rate]).to be_within(0.01).of(1.0/3)
        expect(m[:summary][:policy_blocked_rate]).to be_within(0.01).of(1.0/3)
        expect(m[:summary][:top_agent]).to eq('operational')
      end

      it 'aggregates by_agent' do
        m = described_class.call(AiRequestAudit.all)
        expect(m[:by_agent]['operational']).to eq(2)
        expect(m[:by_agent]['support_faq']).to eq(1)
      end

      it 'aggregates tool_usage' do
        m = described_class.call(AiRequestAudit.all)
        expect(m[:tool_usage][:tool_used_count]).to eq(1)
        expect(m[:tool_usage][:tool_names_frequency]['get_merchant_account']).to eq(1)
      end

      it 'aggregates policy metrics' do
        m = described_class.call(AiRequestAudit.all)
        expect(m[:policy][:authorization_denied_count]).to eq(1)
        expect(m[:policy][:policy_blocked_rate]).to be_within(0.01).of(1.0/3)
      end

      it 'aggregates followup metrics' do
        m = described_class.call(AiRequestAudit.all)
        expect(m[:followup][:followup_count]).to eq(1)
        expect(m[:followup][:by_type]['time_range_adjustment']).to eq(1)
      end

      it 'returns recent_requests with safe fields only' do
        m = described_class.call(AiRequestAudit.all)
        expect(m[:recent_requests].size).to eq(3)
        r = m[:recent_requests].first
        expect(r).to have_key(:created_at)
        expect(r).to have_key(:agent_key)
        expect(r).to have_key(:success)
        expect(r).to have_key(:request_id)
        expect(r).not_to have_key(:error_message)
        expect(r).not_to have_key(:parsed_entities)
      end

      it 'aggregates skill_usage when invoked_skills present' do
        create_audit(invoked_skills: [
          { 'skill_key' => 'payment_state_explainer', 'invoked' => true, 'success' => true, 'phase' => 'post_tool' },
          { 'skill_key' => 'payment_state_explainer', 'invoked' => true, 'success' => true, 'phase' => 'post_tool' }
        ])
        create_audit(invoked_skills: [{ 'skill_key' => 'followup_rewriter', 'invoked' => true, 'success' => false }])
        m = described_class.call(AiRequestAudit.all)
        expect(m[:skill_usage][:skill_invoked_count]).to eq(3)
        expect(m[:skill_usage][:skill_keys_frequency]['payment_state_explainer']).to eq(2)
        expect(m[:skill_usage][:skill_keys_frequency]['followup_rewriter']).to eq(1)
        expect(m[:skill_usage][:success_rate]).to be_within(0.01).of(2.0 / 3)
      end
    end
  end

  def create_audit(**attrs)
    AiRequestAudit.create!(
      {
        request_id: SecureRandom.hex(8),
        endpoint: 'dashboard',
        agent_key: 'operational',
        merchant_id: merchant.id
      }.merge(attrs)
    )
  end
end
