# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Policy::Engine do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }
  let(:other_merchant) { create_merchant_with_api_key(name: 'Other').first }
  let(:context) { { 'merchant_id' => merchant.id } }
  let(:parsed_request) { { intent: { tool_name: 'get_payment_intent' }, args: { payment_intent_id: 1 } } }

  describe '.call' do
    it 'returns an Engine instance' do
      engine = described_class.call(context: context)
      expect(engine).to be_a(described_class)
      expect(engine.merchant_id).to eq(merchant.id)
    end
  end

  describe '#allow_tool?' do
    it 'allows known tool and wraps decision with :tool' do
      engine = described_class.call(context: context, parsed_request: parsed_request)
      d = engine.allow_tool?(tool_name: 'get_payment_intent', context: context, parsed_request: parsed_request)
      expect(d.allowed?).to be true
      expect(d.decision_type).to eq(:tool)
    end

    it 'denies unknown tool with decision_type :tool' do
      engine = described_class.call(context: context)
      d = engine.allow_tool?(tool_name: 'fetch_all_merchants_data', context: context, parsed_request: { args: {} })
      expect(d.denied?).to be true
      expect(d.decision_type).to eq(:tool)
      expect(d.reason_code).to eq(Ai::Policy::Authorization::REASON_TOOL_NOT_ALLOWED)
    end

    it 'denies when merchant_id missing' do
      engine = described_class.call(context: {})
      d = engine.allow_tool?(tool_name: 'get_payment_intent', context: {}, parsed_request: { args: { payment_intent_id: 1 } })
      expect(d.denied?).to be true
      expect(d.reason_code).to eq(Ai::Policy::Authorization::REASON_MERCHANT_REQUIRED)
    end
  end

  describe '#allow_orchestration?' do
    it 'allows when merchant_id and intent present' do
      engine = described_class.call(context: context, parsed_request: parsed_request)
      d = engine.allow_orchestration?(context: context, parsed_request: parsed_request)
      expect(d.allowed?).to be true
      expect(d.decision_type).to eq(:orchestration)
    end

    it 'denies when merchant_id missing' do
      engine = described_class.call(context: {})
      d = engine.allow_orchestration?(context: {}, parsed_request: parsed_request)
      expect(d.denied?).to be true
      expect(d.reason_code).to eq(described_class::REASON_MERCHANT_REQUIRED)
      expect(d.decision_type).to eq(:orchestration)
    end

    it 'denies when intent and resolved_intent blank' do
      engine = described_class.call(context: context, parsed_request: { intent: nil, resolved_intent: nil })
      d = engine.allow_orchestration?(context: context, parsed_request: { intent: nil, resolved_intent: nil })
      expect(d.denied?).to be true
      expect(d.reason_code).to eq(described_class::REASON_ORCHESTRATION_BLOCKED)
      expect(d.decision_type).to eq(:orchestration)
    end

    it 'allows when resolved_intent present and intent blank' do
      engine = described_class.call(context: context, parsed_request: { intent: nil, resolved_intent: { tool_name: 'get_merchant_account' } })
      d = engine.allow_orchestration?(context: context, parsed_request: { intent: nil, resolved_intent: { tool_name: 'get_merchant_account' } })
      expect(d.allowed?).to be true
    end
  end

  describe '#allow_memory_reuse?' do
    it 'allows when merchant_id present' do
      engine = described_class.call(context: context)
      d = engine.allow_memory_reuse?(context: context, memory_candidate: { merchant_id: merchant.id }, parsed_request: nil)
      expect(d.allowed?).to be true
      expect(d.decision_type).to eq(:memory_reuse)
    end

    it 'denies when merchant_id missing' do
      engine = described_class.call(context: {})
      d = engine.allow_memory_reuse?(context: {}, memory_candidate: {}, parsed_request: nil)
      expect(d.denied?).to be true
      expect(d.reason_code).to eq(described_class::REASON_MERCHANT_REQUIRED)
      expect(d.decision_type).to eq(:memory_reuse)
    end
  end

  describe '#allow_followup_inheritance?' do
    it 'denies when entity_type or entity_id blank' do
      engine = described_class.call(context: context)
      d = engine.allow_followup_inheritance?(context: context, inherited_item: { entity_type: 'payment_intent', entity_id: nil }, parsed_request: nil)
      expect(d.denied?).to be true
      expect(d.reason_code).to eq('entity_invalid')
      expect(d.decision_type).to eq(:followup_inheritance)
    end

    it 'allows when entity owned by current merchant' do
      pi = merchant.payment_intents.create!(
        customer_id: merchant.customers.create!(email: 'c@x.com', merchant_id: merchant.id).id,
        amount_cents: 1000,
        currency: 'USD'
      )
      engine = described_class.call(context: context)
      d = engine.allow_followup_inheritance?(context: context, inherited_item: { entity_type: 'payment_intent', entity_id: pi.id }, parsed_request: nil)
      expect(d.allowed?).to be true
      expect(d.decision_type).to eq(:followup_inheritance)
    end

    it 'denies when entity owned by another merchant' do
      pi = merchant.payment_intents.create!(
        customer_id: merchant.customers.create!(email: 'c@x.com', merchant_id: merchant.id).id,
        amount_cents: 1000,
        currency: 'USD'
      )
      engine = described_class.call(context: { 'merchant_id' => other_merchant.id })
      d = engine.allow_followup_inheritance?(context: { 'merchant_id' => other_merchant.id }, inherited_item: { entity_type: 'payment_intent', entity_id: pi.id }, parsed_request: nil)
      expect(d.denied?).to be true
      expect(d.decision_type).to eq(:followup_inheritance)
    end
  end

  describe '#allow_source_composition?' do
    it 'allows normal source types' do
      engine = described_class.call(context: context)
      d = engine.allow_source_composition?(source_types: %w[tool docs], context: context, parsed_request: nil)
      expect(d.allowed?).to be true
      expect(d.decision_type).to eq(:source_composition)
    end

    it 'denies when merchant_id missing' do
      engine = described_class.call(context: {})
      d = engine.allow_source_composition?(source_types: %w[tool docs], context: {}, parsed_request: nil)
      expect(d.denied?).to be true
      expect(d.reason_code).to eq(described_class::REASON_MERCHANT_REQUIRED)
    end

    it 'denies raw_payload or internal source types' do
      engine = described_class.call(context: context)
      d = engine.allow_source_composition?(source_types: %w[tool raw_payload], context: context, parsed_request: nil)
      expect(d.denied?).to be true
      expect(d.reason_code).to eq(described_class::REASON_SOURCE_COMPOSITION_BLOCKED)
      expect(d.decision_type).to eq(:source_composition)
    end
  end

  describe '#allow_debug_exposure?' do
    it 'denies when AI_DEBUG not enabled' do
      allow(::Ai::Observability::EventLogger).to receive(:ai_debug_enabled?).and_return(false)
      engine = described_class.call(context: context)
      d = engine.allow_debug_exposure?(context: context, debug_payload: { latency_ms: 100 })
      expect(d.denied?).to be true
      expect(d.reason_code).to eq(described_class::REASON_DEBUG_RESTRICTED)
      expect(d.decision_type).to eq(:debug_exposure)
    end

    it 'allows when AI_DEBUG enabled and payload has no secrets' do
      allow(::Ai::Observability::EventLogger).to receive(:ai_debug_enabled?).and_return(true)
      engine = described_class.call(context: context)
      d = engine.allow_debug_exposure?(context: context, debug_payload: { latency_ms: 100, selected_agent: 'support' })
      expect(d.allowed?).to be true
      expect(d.decision_type).to eq(:debug_exposure)
    end

    it 'denies when payload contains prompt or api_key' do
      allow(::Ai::Observability::EventLogger).to receive(:ai_debug_enabled?).and_return(true)
      engine = described_class.call(context: context)
      d = engine.allow_debug_exposure?(context: context, debug_payload: { latency_ms: 100, prompt: 'user message' })
      expect(d.denied?).to be true
      expect(d.reason_code).to eq(described_class::REASON_DEBUG_RESTRICTED)
      d2 = engine.allow_debug_exposure?(context: context, debug_payload: { api_key: 'sk_xxx' })
      expect(d2.denied?).to be true
    end
  end

  describe '#allow_deterministic_data_exposure?' do
    it 'allows when data blank' do
      engine = described_class.call(context: context)
      d = engine.allow_deterministic_data_exposure?(resource_type: 'payment_intent', context: context, parsed_request: nil, data: nil)
      expect(d.allowed?).to be true
      expect(d.decision_type).to eq(:deterministic_data)
    end

    it 'denies when merchant_id missing' do
      engine = described_class.call(context: {})
      d = engine.allow_deterministic_data_exposure?(resource_type: 'payment_intent', context: {}, parsed_request: nil, data: { id: 1 })
      expect(d.denied?).to be true
      expect(d.reason_code).to eq(described_class::REASON_MERCHANT_REQUIRED)
    end

    it 'delegates to authorization allow_composed_data? when data present' do
      engine = described_class.call(context: context)
      d = engine.allow_deterministic_data_exposure?(resource_type: 'payment_intent', context: context, parsed_request: nil, data: { merchant_id: merchant.id, id: 1 })
      expect(d.allowed?).to be true
      expect(d.decision_type).to eq(:deterministic_data)
    end
  end

  describe '#allow_docs_only_fallback?' do
    it 'allows when merchant_id present' do
      engine = described_class.call(context: context)
      d = engine.allow_docs_only_fallback?(context: context, parsed_request: nil)
      expect(d.allowed?).to be true
      expect(d.decision_type).to eq(:docs_fallback)
    end

    it 'denies when merchant_id missing' do
      engine = described_class.call(context: {})
      d = engine.allow_docs_only_fallback?(context: {}, parsed_request: nil)
      expect(d.denied?).to be true
      expect(d.reason_code).to eq(described_class::REASON_MERCHANT_REQUIRED)
      expect(d.decision_type).to eq(:docs_fallback)
    end
  end

  describe '#authorization' do
    it 'exposes Authorization instance for record-level checks' do
      engine = described_class.call(context: context)
      expect(engine.authorization).to be_a(Ai::Policy::Authorization)
      expect(engine.authorization.merchant_id).to eq(merchant.id)
    end
  end

  describe '.denied_message' do
    it 'returns same safe message as Authorization' do
      expect(described_class.denied_message).to eq(Ai::Policy::Authorization.denied_message)
      expect(described_class.denied_message).to eq('Could not fetch data.')
    end
  end
end
