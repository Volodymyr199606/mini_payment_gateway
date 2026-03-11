# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::AuditTrail::Writer do
  include ApiHelpers

  describe '.write' do
    let(:merchant) { create_merchant_with_api_key.first }
    let(:base_record) do
      {
        request_id: 'test-req-123',
        endpoint: 'dashboard',
        merchant_id: merchant.id,
        agent_key: 'operational',
        success: true
      }
    end

    it 'persists an audit record' do
      expect {
        described_class.write(base_record)
      }.to change(AiRequestAudit, :count).by(1)

      audit = AiRequestAudit.last
      expect(audit.request_id).to eq('test-req-123')
      expect(audit.endpoint).to eq('dashboard')
      expect(audit.merchant_id).to eq(merchant.id)
      expect(audit.agent_key).to eq('operational')
      expect(audit.success).to be(true)
    end

    it 'does not store secrets in error_message' do
      record = base_record.merge(
        success: false,
        error_class: 'AuthError',
        error_message: 'Invalid api_key=sk_live_abc123xyz'
      )
      described_class.write(record)
      audit = AiRequestAudit.last
      expect(audit.error_message).not_to include('sk_live_abc123xyz')
      expect(audit.error_message).to include('[REDACTED]')
    end

    it 'truncates long error_message' do
      long_msg = 'x' * 600
      record = base_record.merge(success: false, error_message: long_msg)
      described_class.write(record)
      audit = AiRequestAudit.last
      expect(audit.error_message.length).to be <= 500
    end

    it 'records tool/memory/fallback/citation metadata correctly' do
      record = base_record.merge(
        retriever_key: 'DocsRetriever',
        composition_mode: 'docs_only',
        tool_used: false,
        tool_names: [],
        fallback_used: true,
        citation_reask_used: false,
        memory_used: true,
        summary_used: true,
        citations_count: 2,
        retrieved_sections_count: 3,
        latency_ms: 150,
        model_used: 'llama-3.3-70b'
      )
      described_class.write(record)
      audit = AiRequestAudit.last
      expect(audit.retriever_key).to eq('DocsRetriever')
      expect(audit.composition_mode).to eq('docs_only')
      expect(audit.tool_used).to be(false)
      expect(audit.fallback_used).to be(true)
      expect(audit.memory_used).to be(true)
      expect(audit.summary_used).to be(true)
      expect(audit.citations_count).to eq(2)
      expect(audit.retrieved_sections_count).to eq(3)
      expect(audit.latency_ms).to eq(150)
      expect(audit.model_used).to eq('llama-3.3-70b')
    end

    it 'returns nil and does not raise when record is invalid' do
      invalid = { request_id: nil, endpoint: nil, agent_key: nil }
      result = described_class.write(invalid)
      expect(result).to be_nil
    end

    it 'returns nil on persistence failure and does not raise' do
      allow(AiRequestAudit).to receive(:create!).and_raise(ActiveRecord::StatementInvalid.new('DB error'))
      result = nil
      expect { result = described_class.write(base_record) }.not_to raise_error
      expect(result).to be_nil
    end
  end
end
