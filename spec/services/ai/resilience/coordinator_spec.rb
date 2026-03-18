# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Resilience::Coordinator do
  describe '.infer_stage' do
    it 'infers generation from Groq/Faraday errors' do
      expect(described_class.infer_stage(StandardError.new('Groq API error'))).to eq(:generation)
    end

    it 'infers retrieval from retrieval-related messages' do
      expect(described_class.infer_stage(StandardError.new('retrieval failed'))).to eq(:retrieval)
    end

    it 'infers streaming from stream-related messages' do
      expect(described_class.infer_stage(StandardError.new('stream closed'))).to eq(:streaming)
    end

    it 'returns unknown for generic errors' do
      expect(described_class.infer_stage(StandardError.new('something broke'))).to eq(:unknown)
    end

    it 'infers generation from api_key / not set messages' do
      expect(described_class.infer_stage(StandardError.new('GROQ_API_KEY not set'))).to eq(:generation)
      expect(described_class.infer_stage(StandardError.new('api_key missing'))).to eq(:generation)
    end
  end

  describe '.plan_fallback' do
    it 'returns degraded decision with fallback_mode' do
      d = described_class.plan_fallback(failure_stage: :generation, context: {})
      expect(d.degraded?).to be true
      expect(d.failure_stage).to eq(:generation)
      expect(d.fallback_mode).to eq(:safe_failure_message)
      expect(d.safe_message).to be_present
    end

    it 'chooses tool_only when context has tool_data' do
      d = described_class.plan_fallback(failure_stage: :generation, context: { tool_data: { id: 1 } })
      expect(d.fallback_mode).to eq(:tool_only)
    end

    it 'chooses docs_only when tool fails but context_text present' do
      d = described_class.plan_fallback(failure_stage: :tool, context: { context_text: 'doc content' })
      expect(d.fallback_mode).to eq(:docs_only)
    end

    it 'uses API key message when exception is api_key related' do
      d = described_class.plan_fallback(failure_stage: :generation, context: {}, exception: StandardError.new('GROQ_API_KEY not set'))
      expect(d.safe_message).to include('GROQ_API_KEY')
    end
  end

  describe '.build_safe_response' do
    it 'returns response hash with reply and agent_key' do
      d = described_class.plan_fallback(failure_stage: :generation, context: {})
      r = described_class.build_safe_response(decision: d, context: {})
      expect(r[:reply]).to be_present
      expect(r[:agent_key]).to eq('resilience_fallback')
      expect(r[:citations]).to eq([])
      expect(r[:fallback_used]).to be true
    end

    it 'uses tool_data when fallback_mode is tool_only' do
      d = described_class.plan_fallback(failure_stage: :generation, context: { tool_data: { id: 1 } })
      r = described_class.build_safe_response(decision: d, context: { tool_data: { id: 1 }, tool_name: 'get_merchant_account' })
      expect(r[:data]).to eq({ id: 1 })
    end
  end

  describe '.safe_message_for' do
    it 'returns message for known stage' do
      expect(described_class.safe_message_for(:generation)).to include('trouble generating')
    end

    it 'returns unknown message for unknown stage' do
      expect(described_class.safe_message_for(:unknown)).to include('try again')
    end
  end
end
