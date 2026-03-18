# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Debug payload contract' do
  describe 'EventLogger.build_debug_payload output' do
    it 'includes schema_version and does not include prompt or api_key' do
      debug = Ai::Observability::EventLogger.build_debug_payload(
        selected_agent: 'support_faq',
        selected_retriever: 'docs',
        latency_ms: 100,
        citations_count: 2,
        execution_plan: Ai::Performance::ExecutionPlan.full_agent
      )
      expect(debug).to have_key(:schema_version)
      expect(debug[:schema_version]).to eq(Ai::Contracts::DEBUG_PAYLOAD_VERSION)
      AiContractHelpers.assert_no_forbidden_keys!(debug, contract_name: 'Debug payload')
    end

    it 'execution_plan slice has stable keys when present' do
      plan = Ai::Performance::ExecutionPlan.new(
        execution_mode: :agent_full,
        skip_retrieval: false,
        skip_memory: false,
        skip_orchestration: true,
        retrieval_budget_reduced: false,
        reason_codes: [],
        metadata: {}
      )
      debug = Ai::Observability::EventLogger.build_debug_payload(
        selected_agent: 'support_faq',
        execution_plan: plan
      )
      ep = debug[:execution_plan]
      expect(ep).to be_a(Hash)
      expect(ep).to have_key(:execution_mode)
      expect(ep).to have_key(:retrieval_skipped)
      expect(ep).to have_key(:memory_skipped)
      expect(ep).to have_key(:reason_codes)
    end
  end

  describe 'DebugPayload contract STABLE_KEYS' do
    it 'DebugPayload::STABLE_KEYS does not include prompt or api_key' do
      Ai::Contracts::DebugPayload::STABLE_KEYS.each do |key|
        expect(key.to_s.downcase).not_to include('prompt'), "Debug STABLE_KEYS must not include prompt-like key: #{key}"
        expect(key.to_s.downcase).not_to include('api_key'), "Debug STABLE_KEYS must not include api_key: #{key}"
      end
    end
  end
end
