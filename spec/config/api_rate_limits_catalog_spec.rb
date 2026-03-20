# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApiRateLimits::Catalog do
  describe '.resolve' do
    it 'maps payment intent mutations' do
      expect(described_class.resolve(controller_path: 'api/v1/payment_intents', action_name: 'authorize')).to eq('payment_mutation')
      expect(described_class.resolve(controller_path: 'api/v1/payment_intents', action_name: 'show')).to eq('read')
    end

    it 'maps refunds create' do
      expect(described_class.resolve(controller_path: 'api/v1/refunds', action_name: 'create')).to eq('payment_mutation')
    end

    it 'maps AI chat' do
      expect(described_class.resolve(controller_path: 'api/v1/ai/chat', action_name: 'create')).to eq('ai')
    end
  end
end
