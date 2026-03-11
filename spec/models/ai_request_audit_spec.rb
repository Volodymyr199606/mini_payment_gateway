# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiRequestAudit do
  include ApiHelpers

  describe 'validations' do
    it 'requires request_id, endpoint, agent_key' do
      audit = described_class.new(request_id: nil, endpoint: 'dashboard', agent_key: 'x', success: true)
      expect(audit).not_to be_valid
      expect(audit.errors[:request_id]).to be_present
    end

    it 'is valid with required attributes' do
      merchant = create_merchant_with_api_key.first
      audit = described_class.new(
        request_id: 'req-1',
        endpoint: 'dashboard',
        agent_key: 'operational',
        success: true,
        merchant_id: merchant.id
      )
      expect(audit).to be_valid
    end
  end

  describe 'scopes' do
    let(:merchant) { create_merchant_with_api_key.first }

    before do
      described_class.create!(request_id: 'r1', endpoint: 'dashboard', agent_key: 'a', success: true, merchant_id: merchant.id)
      described_class.create!(request_id: 'r2', endpoint: 'api', agent_key: 'b', success: false, merchant_id: merchant.id)
    end

    it 'recent orders by created_at desc' do
      expect(described_class.recent.pluck(:request_id)).to eq(%w[r2 r1])
    end

    it 'for_merchant filters by merchant' do
      other = create_merchant_with_api_key.first
      described_class.create!(request_id: 'r3', endpoint: 'api', agent_key: 'c', success: true, merchant_id: other.id)
      expect(described_class.for_merchant(merchant).count).to eq(2)
      expect(described_class.for_merchant(other).count).to eq(1)
    end
  end
end
