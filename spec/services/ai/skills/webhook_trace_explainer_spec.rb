# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Skills::WebhookTraceExplainer do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }

  describe '#execute' do
    it 'returns failure when merchant_id missing' do
      result = described_class.new.execute(context: {})
      expect(result.failure?).to be true
      expect(result.error_code).to eq('missing_context')
    end

    it 'returns failure when webhook not found' do
      result = described_class.new.execute(context: { merchant_id: merchant.id, webhook_event_id: 999_999 })
      expect(result.failure?).to be true
      expect(result.error_code).to eq('entity_not_found')
    end

    it 'explains pending webhook' do
      evt = merchant.webhook_events.create!(
        event_type: 'payment_intent.captured',
        payload: { 'id' => 'evt_1' },
        delivery_status: 'pending',
        attempts: 0
      )
      result = described_class.new.execute(context: { merchant_id: merchant.id, webhook_event_id: evt.id })
      expect(result.success).to be true
      expect(result.explanation.downcase).to include('pending')
      expect(result.data['delivery_status']).to eq('pending')
      expect(result.deterministic).to be true
    end

    it 'explains succeeded webhook' do
      evt = merchant.webhook_events.create!(
        event_type: 'payment_intent.succeeded',
        payload: { 'id' => 'evt_succ' },
        delivery_status: 'succeeded',
        attempts: 1
      )
      result = described_class.new.execute(context: { merchant_id: merchant.id, webhook_event_id: evt.id })
      expect(result.success).to be true
      expect(result.explanation.downcase).to include('succeeded').or include('delivered')
    end

    it 'works with pre-fetched webhook hash' do
      result = described_class.new.execute(
        context: {
          merchant_id: merchant.id,
          webhook_event: { id: 1, event_type: 'charge.failed', delivery_status: 'failed', attempts: 3 }
        }
      )
      expect(result.success).to be true
      expect(result.explanation.downcase).to include('failed')
      expect(result.data['delivery_status']).to eq('failed')
    end

    it 'includes audit metadata' do
      evt = merchant.webhook_events.create!(
        event_type: 'payment_intent.captured',
        payload: { 'id' => 'evt_cap' },
        delivery_status: 'succeeded',
        attempts: 1
      )
      result = described_class.new.execute(context: { merchant_id: merchant.id, webhook_event_id: evt.id, agent_key: 'operational' })
      expect(result.metadata['merchant_id']).to eq(merchant.id.to_s)
    end
  end
end
