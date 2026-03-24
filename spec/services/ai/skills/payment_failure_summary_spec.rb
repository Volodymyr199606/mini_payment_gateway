# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Skills::PaymentFailureSummary do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }

  describe '#execute' do
    it 'summarizes failed payment intent' do
      context = {
        merchant_id: merchant.id,
        payment_intent: { id: 1, status: 'failed', amount_cents: 1000, currency: 'USD' }
      }
      result = described_class.new.execute(context: context)

      expect(result.success).to be true
      expect(result.explanation).to include('**Payment failure:**')
      expect(result.explanation).to include('failed')
      expect(result.explanation).to include('$10.00')
      expect(result.data['status']).to eq('failed')
      expect(result.data['lifecycle_stage']).to eq('payment_intent')
    end

    it 'summarizes canceled payment intent' do
      context = {
        merchant_id: merchant.id,
        payment_intent: { id: 2, status: 'canceled', amount_cents: 500, currency: 'USD' }
      }
      result = described_class.new.execute(context: context)

      expect(result.success).to be true
      expect(result.explanation).to include('**Payment voided:**')
      expect(result.explanation).to include('canceled')
    end

    it 'summarizes failed transaction (authorize)' do
      context = {
        merchant_id: merchant.id,
        transaction: { id: 10, kind: 'authorize', status: 'failed', amount_cents: 2000 }
      }
      result = described_class.new.execute(context: context)

      expect(result.success).to be true
      expect(result.explanation).to include('**Transaction failure:**')
      expect(result.explanation).to include('authorization')
      expect(result.data['lifecycle_stage']).to eq('authorization')
    end

    it 'summarizes failed transaction (capture)' do
      context = {
        merchant_id: merchant.id,
        transaction: { id: 11, kind: 'capture', status: 'failed', amount_cents: 1500 }
      }
      result = described_class.new.execute(context: context)

      expect(result.success).to be true
      expect(result.explanation).to include('capture')
      expect(result.data['lifecycle_stage']).to eq('capture')
    end

    it 'returns failure when no failure data' do
      context = {
        merchant_id: merchant.id,
        payment_intent: { id: 3, status: 'captured', amount_cents: 1000, currency: 'USD' }
      }
      result = described_class.new.execute(context: context)

      expect(result.failure?).to be true
      expect(result.error_code).to eq('no_failure_data')
    end

    it 'returns failure when merchant_id missing' do
      context = { payment_intent: { id: 1, status: 'failed' } }
      result = described_class.new.execute(context: context)

      expect(result.failure?).to be true
      expect(result.error_code).to eq('missing_context')
    end
  end
end
