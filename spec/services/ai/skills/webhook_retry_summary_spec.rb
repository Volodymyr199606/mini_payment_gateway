# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Skills::WebhookRetrySummary do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }

  describe '#execute' do
    it 'summarizes delivered webhook' do
      context = {
        merchant_id: merchant.id,
        webhook_event: { id: 1, event_type: 'payment_intent.captured', delivery_status: 'succeeded', attempts: 1 }
      }
      result = described_class.new.execute(context: context)

      expect(result.success).to be true
      expect(result.explanation).to include('**Webhook delivered:**')
      expect(result.explanation).to include('delivered successfully')
      expect(result.data['delivery_status']).to eq('succeeded')
    end

    it 'summarizes pending/retrying webhook' do
      context = {
        merchant_id: merchant.id,
        webhook_event: { id: 2, event_type: 'charge.failed', delivery_status: 'pending', attempts: 1 }
      }
      result = described_class.new.execute(context: context)

      expect(result.success).to be true
      expect(result.explanation).to include('**Webhook retrying:**')
      expect(result.explanation).to include('pending')
      expect(result.explanation).to include('Retrying')
    end

    it 'summarizes exhausted/failed webhook' do
      context = {
        merchant_id: merchant.id,
        webhook_event: { id: 3, event_type: 'refund.created', delivery_status: 'failed', attempts: 3 }
      }
      result = described_class.new.execute(context: context)

      expect(result.success).to be true
      expect(result.explanation).to include('**Webhook delivery exhausted:**')
      expect(result.explanation).to include('failed')
      expect(result.explanation).to include('3 attempt')
    end

    it 'accepts webhook_event from deterministic_data' do
      context = {
        merchant_id: merchant.id,
        deterministic_data: { webhook_event: { id: 4, event_type: 'test', delivery_status: 'succeeded', attempts: 1 } }
      }
      result = described_class.new.execute(context: context)

      expect(result.success).to be true
      expect(result.explanation).to include('delivered successfully')
    end

    it 'returns failure when no webhook data' do
      context = { merchant_id: merchant.id }
      result = described_class.new.execute(context: context)

      expect(result.failure?).to be true
      expect(result.error_code).to eq('no_webhook_data')
    end

    it 'returns failure when merchant_id missing' do
      context = { webhook_event: { id: 1, delivery_status: 'succeeded' } }
      result = described_class.new.execute(context: context)

      expect(result.failure?).to be true
      expect(result.error_code).to eq('missing_context')
    end
  end
end
