# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Observability::EventLogger do
  describe '.build_debug_payload' do
    it 'returns hash with expected debug fields' do
      payload = described_class.build_debug_payload(
        selected_agent: 'operational',
        selected_retriever: 'DocsRetriever',
        graph_enabled: false,
        vector_enabled: false,
        retrieved_sections_count: 3,
        citations_count: 3,
        fallback_used: false,
        citation_reask_used: false,
        model_used: 'llama-3.3-70b',
        memory_used: false,
        summary_used: false,
        latency_ms: 450
      )
      expect(payload[:selected_agent]).to eq('operational')
      expect(payload[:selected_retriever]).to eq('DocsRetriever')
      expect(payload[:graph_enabled]).to be(false)
      expect(payload[:vector_enabled]).to be(false)
      expect(payload[:retrieved_sections_count]).to eq(3)
      expect(payload[:citations_count]).to eq(3)
      expect(payload[:fallback_used]).to be(false)
      expect(payload[:citation_reask_used]).to be(false)
      expect(payload[:model_used]).to eq('llama-3.3-70b')
      expect(payload[:memory_used]).to be(false)
      expect(payload[:summary_used]).to be(false)
      expect(payload[:latency_ms]).to eq(450)
    end

    it 'includes retriever_debug when provided' do
      retriever_debug = { seed_section_ids: ['a'], context_truncated: false }
      payload = described_class.build_debug_payload(
        selected_agent: 'support_faq',
        selected_retriever: 'GraphExpandedRetriever',
        graph_enabled: true,
        vector_enabled: false,
        retrieved_sections_count: 5,
        citations_count: 5,
        fallback_used: false,
        citation_reask_used: false,
        model_used: nil,
        memory_used: false,
        summary_used: false,
        latency_ms: 200,
        retriever_debug: retriever_debug
      )
      expect(payload[:retriever]).to eq(retriever_debug)
    end

    it 'includes execution_plan when provided' do
      plan = Ai::Performance::ExecutionPlan.new(
        execution_mode: :deterministic_only,
        skip_retrieval: true,
        skip_memory: true,
        skip_orchestration: false,
        retrieval_budget_reduced: false,
        reason_codes: %w[intent_present deterministic_sufficient],
        metadata: {}
      )
      payload = described_class.build_debug_payload(
        selected_agent: 'operational',
        selected_retriever: nil,
        graph_enabled: false,
        vector_enabled: false,
        retrieved_sections_count: 0,
        citations_count: 0,
        fallback_used: false,
        citation_reask_used: false,
        model_used: nil,
        memory_used: false,
        summary_used: false,
        latency_ms: 50,
        execution_plan: plan
      )
      expect(payload[:execution_plan]).to eq(
        execution_mode: :deterministic_only,
        retrieval_skipped: true,
        memory_skipped: true,
        orchestration_skipped: false,
        retrieval_budget_reduced: false,
        reason_codes: %w[intent_present deterministic_sufficient]
      )
    end

    it 'omits execution_plan when nil' do
      payload = described_class.build_debug_payload(
        selected_agent: 'operational',
        selected_retriever: 'DocsRetriever',
        graph_enabled: false,
        vector_enabled: false,
        retrieved_sections_count: 2,
        citations_count: 2,
        fallback_used: false,
        citation_reask_used: false,
        model_used: nil,
        memory_used: false,
        summary_used: false,
        latency_ms: 100,
        retriever_debug: nil
      )
      expect(payload).not_to have_key(:execution_plan)
    end

    it 'omits retriever_debug when nil or empty' do
      payload = described_class.build_debug_payload(
        selected_agent: 'support_faq',
        selected_retriever: 'DocsRetriever',
        graph_enabled: false,
        vector_enabled: false,
        retrieved_sections_count: 2,
        citations_count: 2,
        fallback_used: false,
        citation_reask_used: false,
        model_used: nil,
        memory_used: false,
        summary_used: false,
        latency_ms: 100,
        retriever_debug: nil
      )
      expect(payload).not_to have_key(:retriever)
    end
  end

  describe '.log_retrieval' do
    it 'builds retrieval metadata with all expected fields' do
      expect(Rails.logger).to receive(:info) do |json_str|
        payload = JSON.parse(json_str)
        expect(payload['event']).to eq('ai_retrieval')
        expect(payload['retriever']).to eq('DocsRetriever')
        expect(payload['query']).to eq('How do refunds work?')
        expect(payload['agent_key']).to eq('operational')
        expect(payload['seed_sections_count']).to eq(3)
        expect(payload['expanded_sections_count']).to eq(2)
        expect(payload['final_sections_count']).to eq(4)
        expect(payload['context_text_length']).to eq(1200)
        expect(payload['context_truncated']).to be(false)
        expect(payload['citations_count']).to eq(4)
      end
      described_class.log_retrieval(
        retriever: 'DocsRetriever',
        query: 'How do refunds work?',
        agent_key: 'operational',
        seed_sections_count: 3,
        expanded_sections_count: 2,
        final_sections_count: 4,
        context_text_length: 1200,
        context_truncated: false,
        citations_count: 4
      )
    end
  end

  describe '.log_guardrail' do
    it 'logs guardrail event with metadata' do
      expect(Rails.logger).to receive(:info) do |json_str|
        payload = JSON.parse(json_str)
        expect(payload['event']).to eq('ai_guardrail_empty_retrieval_fallback')
        expect(payload['citations_count']).to eq(0)
        expect(payload['context_length']).to eq(0)
      end
      described_class.log_guardrail(
        event: 'empty_retrieval_fallback',
        request_id: 'req-123',
        citations_count: 0,
        context_length: 0
      )
    end

    it 'logs citation_reask event' do
      expect(Rails.logger).to receive(:info) do |json_str|
        payload = JSON.parse(json_str)
        expect(payload['event']).to eq('ai_guardrail_citation_reask')
        expect(payload['citations_count']).to eq(2)
      end
      described_class.log_guardrail(
        event: 'citation_reask',
        request_id: 'req-456',
        citations_count: 2,
        context_length: 800
      )
    end

    it 'logs secret_redaction event' do
      expect(Rails.logger).to receive(:info) do |json_str|
        payload = JSON.parse(json_str)
        expect(payload['event']).to eq('ai_guardrail_secret_redaction')
      end
      described_class.log_guardrail(
        event: 'secret_redaction',
        request_id: 'req-789',
        citations_count: 1,
        context_length: 500
      )
    end
  end

  describe '.log_execution_plan' do
    it 'logs ai_execution_plan event' do
      expect(Rails.logger).to receive(:info) do |json_str|
        payload = JSON.parse(json_str)
        expect(payload['event']).to eq('ai_execution_plan')
        expect(payload['execution_mode']).to eq('deterministic_only')
        expect(payload['retrieval_skipped']).to be(true)
        expect(payload['memory_skipped']).to be(true)
        expect(payload['reason_codes']).to eq(%w[intent_present])
      end
      described_class.log_execution_plan(
        execution_mode: :deterministic_only,
        retrieval_skipped: true,
        memory_skipped: true,
        orchestration_skipped: false,
        retrieval_budget_reduced: false,
        reason_codes: %w[intent_present],
        request_id: 'req-plan-1'
      )
    end
  end

  describe '.log_tool_call' do
    it 'logs ai_tool_call event with metadata' do
      expect(Rails.logger).to receive(:info) do |json_str|
        payload = JSON.parse(json_str)
        expect(payload['event']).to eq('ai_tool_call')
        expect(payload['tool_name']).to eq('get_merchant_account')
        expect(payload['success']).to be(true)
        expect(payload['latency_ms']).to eq(10)
      end
      described_class.log_tool_call(
        request_id: 'req-1',
        merchant_id: 1,
        tool_name: 'get_merchant_account',
        args: { merchant_id: 1 },
        success: true,
        latency_ms: 10
      )
    end
  end

  describe '.ai_debug_enabled?' do
    it 'returns true when AI_DEBUG=true' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('AI_DEBUG').and_return('true')
      expect(described_class.ai_debug_enabled?).to be(true)
    end

    it 'returns true when AI_DEBUG=1' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('AI_DEBUG').and_return('1')
      expect(described_class.ai_debug_enabled?).to be(true)
    end

    it 'returns false when AI_DEBUG is unset or empty' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('AI_DEBUG').and_return('')
      expect(described_class.ai_debug_enabled?).to be(false)
    end

    it 'returns false when AI_DEBUG=false' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('AI_DEBUG').and_return('false')
      expect(described_class.ai_debug_enabled?).to be(false)
    end
  end
end
