# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Analytics::DashboardQuery do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }

  before do
    create_audit(merchant_id: merchant.id, created_at: 2.days.ago)
    create_audit(merchant_id: merchant.id, created_at: 1.day.ago)
    create_audit(merchant_id: nil, created_at: 5.days.ago)
  end

  describe '.call' do
    it 'returns scope filtered by time preset' do
      rel = described_class.call(time_preset: '7d')
      expect(rel.count).to eq(3)
    end

    it 'filters by merchant_id when provided' do
      rel = described_class.call(time_preset: '30d', merchant_id: merchant.id)
      expect(rel.count).to eq(2)
    end

    it 'returns empty for today when no records today' do
      rel = described_class.call(time_preset: 'today')
      expect(rel.count).to eq(0)
    end

    it 'defaults to 7d when preset invalid' do
      rel = described_class.call(time_preset: 'invalid')
      expect(rel).to be_a(ActiveRecord::Relation)
    end
  end

  def create_audit(merchant_id:, created_at:)
    AiRequestAudit.create!(
      request_id: SecureRandom.hex(8),
      endpoint: 'dashboard',
      agent_key: 'operational',
      merchant_id: merchant_id,
      created_at: created_at
    )
  end
end
