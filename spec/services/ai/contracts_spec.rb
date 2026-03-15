# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Ai::Contracts' do
  describe 'version constants' do
    it 'defines expected contract versions' do
      expect(Ai::Contracts::TOOL_RESULT_VERSION).to eq('1')
      expect(Ai::Contracts::RETRIEVAL_RESULT_VERSION).to eq('1')
      expect(Ai::Contracts::COMPOSED_RESPONSE_VERSION).to eq('1')
      expect(Ai::Contracts::AUDIT_PAYLOAD_VERSION).to eq('1')
      expect(Ai::Contracts::DEBUG_PAYLOAD_VERSION).to eq('1')
      expect(Ai::Contracts::EXECUTION_PLAN_VERSION).to eq('1')
      expect(Ai::Contracts::RUN_RESULT_VERSION).to eq('1')
      expect(Ai::Contracts::PARSED_INTENT_VERSION).to eq('1')
      expect(Ai::Contracts::INTENT_RESOLUTION_VERSION).to eq('1')
    end
  end

  describe Ai::Contracts::ParsedIntent do
    it 'round-trips via to_h and from_h' do
      intent = described_class.new(tool_name: 'get_payment_intent', args: { payment_intent_id: 42 })
      h = intent.to_h
      expect(h[:tool_name]).to eq('get_payment_intent')
      expect(h[:args]).to eq({ payment_intent_id: 42 })
      expect(h[:contract_version]).to eq('1')

      restored = described_class.from_h(h)
      expect(restored.tool_name).to eq(intent.tool_name)
      expect(restored.args).to eq(intent.args)
    end

    it 'validates in dev/test' do
      expect { described_class.new(tool_name: '', args: {}).validate! }.to raise_error(ArgumentError, /tool_name/)
    end
  end

  describe Ai::Contracts::ToolResult do
    it 'has stable to_h shape with contract_version' do
      result = described_class.new(success: true, tool_name: 'get_merchant_account', data: { id: 1 })
      h = result.to_h
      expect(h[:success]).to be true
      expect(h[:tool_name]).to eq('get_merchant_account')
      expect(h[:data]).to eq({ id: 1 })
      expect(h[:contract_version]).to eq('1')
    end

    it 'from_h round-trips' do
      original = { success: false, tool_name: 'get_payment_intent', error_code: 'access_denied', authorization_denied: true }
      obj = described_class.from_h(original)
      expect(obj.success?).to be false
      expect(obj.authorization_denied?).to be true
      expect(obj.to_h[:contract_version]).to eq('1')
    end
  end

  describe Ai::Contracts::RetrievalResult do
    it 'has stable to_h shape' do
      result = described_class.new(
        context_text: 'Some context',
        citations: [{ file: 'a.md' }],
        context_truncated: true,
        final_sections_count: 2
      )
      h = result.to_h
      expect(h[:context_text]).to eq('Some context')
      expect(h[:citations].size).to eq(1)
      expect(h[:context_truncated]).to be true
      expect(h[:final_sections_count]).to eq(2)
      expect(h[:contract_version]).to eq('1')
    end
  end

  describe Ai::Contracts::ComposedResponse do
    it 'includes contract_version in composition' do
      result = described_class.new(
        reply: 'Ok',
        agent_key: 'tool:get_payment_intent',
        composition: { composition_mode: 'tool_only' }
      )
      h = result.to_h
      expect(h[:composition][:contract_version]).to eq('1')
      expect(h[:contract_version]).to eq('1')
    end
  end

  describe Ai::Contracts::AuditPayload do
    it 'includes schema_version in to_h' do
      payload = described_class.new(payload: { request_id: 'r1', agent_key: 'operational' })
      expect(payload.to_h[:schema_version]).to eq('1')
      expect(payload.to_h[:request_id]).to eq('r1')
    end
  end

  describe Ai::Contracts::DebugPayload do
    it 'includes schema_version in to_h' do
      payload = described_class.new(payload: { latency_ms: 100 })
      expect(payload.to_h[:schema_version]).to eq('1')
    end
  end

  describe Ai::Performance::ExecutionPlan do
    it 'to_audit_metadata includes contract_version' do
      plan = described_class.new(
        execution_mode: :deterministic_only,
        skip_retrieval: true,
        skip_memory: true,
        skip_orchestration: false,
        reason_codes: %w[intent_present]
      )
      meta = plan.to_audit_metadata
      expect(meta[:contract_version]).to eq('1')
      expect(meta[:execution_mode]).to eq('deterministic_only')
    end

    it 'to_h includes contract_version' do
      plan = described_class.full_agent
      expect(plan.to_h[:contract_version]).to eq('1')
    end
  end

  describe Ai::Orchestration::RunResult do
    it 'to_h includes contract_version' do
      result = described_class.new(
        orchestration_used: true,
        step_count: 1,
        tool_names: ['get_payment_intent'],
        success: true,
        reply_text: 'Done'
      )
      expect(result.to_h[:contract_version]).to eq('1')
      expect(result.to_h[:tool_names]).to eq(['get_payment_intent'])
    end
  end

  describe Ai::Policy::Decision do
    it 'to_h returns stable shape' do
      decision = described_class.allow(decision_type: :tool, metadata: { tool_name: 'get_payment_intent' })
      h = decision.to_h
      expect(h[:allowed]).to be true
      expect(h[:decision_type]).to eq(:tool)
      expect(h[:metadata]).to eq({ tool_name: 'get_payment_intent' })
    end
  end
end
