# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::AuditTrail::DetailPresenter do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }
  let(:audit) do
    AiRequestAudit.create!(
      request_id: 'presenter-test',
      endpoint: 'dashboard',
      agent_key: 'tool:get_payment_intent',
      merchant_id: merchant.id,
      composition_mode: 'tool_only',
      tool_used: true,
      tool_names: ['get_payment_intent'],
      success: true,
      latency_ms: 120,
      citations_count: 0
    )
  end

  describe '.call' do
    it 'returns sections and path_summary' do
      result = described_class.call(audit)
      expect(result).to include(:sections, :path_summary, :path_steps)
      expect(result[:sections]).to be_a(Hash)
      expect(result[:path_summary]).to be_a(String)
      expect(result[:path_steps]).to be_an(Array)
    end

    it 'includes request section with safe fields' do
      result = described_class.call(audit)
      request_section = result[:sections][:request] || {}
      expect(request_section).to include('request_id', 'endpoint', 'created_at')
      expect(request_section['request_id']).to eq('presenter-test')
    end

    it 'includes tool_usage section when tool_used' do
      result = described_class.call(audit)
      tool_section = result[:sections][:tool_usage] || {}
      expect(tool_section['tool_used']).to be true
      expect(tool_section['tool_names']).to be_present
    end

    it 'path_steps includes deterministic explanation when set' do
      if AiRequestAudit.column_names.include?('deterministic_explanation_used')
        audit.update_columns(
          deterministic_explanation_used: true,
          explanation_type: 'payment_intent',
          explanation_key: 'authorized'
        )
      end
      result = described_class.call(audit.reload)
      steps = result[:path_steps]
      expect(steps.any? { |s| s[:label] == 'Deterministic explanation' }).to be true
    end

    it 'does not include unsafe or non-persisted keys' do
      result = described_class.call(audit)
      all_keys = result[:sections].values.flat_map(&:keys).uniq
      unsafe = %w[prompt message history api_key secret token]
      all_keys.each do |k|
        expect(unsafe.any? { |u| k.to_s.downcase.include?(u) }).to be false
      end
    end
  end
end
