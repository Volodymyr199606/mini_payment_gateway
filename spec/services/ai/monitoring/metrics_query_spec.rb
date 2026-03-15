# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Monitoring::MetricsQuery do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }

  def create_audit(**attrs)
    AiRequestAudit.create!(
      {
        request_id: SecureRandom.hex(8),
        endpoint: 'dashboard',
        agent_key: 'operational',
        merchant_id: merchant.id,
        created_at: Time.current
      }.merge(attrs)
    )
  end

  describe '.call' do
    context 'when no audits in window' do
      it 'returns empty metrics with zero total' do
        m = described_class.call(time_window: '1h')
        expect(m[:total_requests]).to eq(0)
        expect(m[:p50_latency_ms]).to be_nil
        expect(m[:p95_latency_ms]).to be_nil
        expect(m[:error_rate]).to eq(0)
        expect(m[:time_window]).to eq('1h')
      end
    end

    context 'when audits exist in window' do
      before do
        base = 1.hour.ago + 1.minute
        create_audit(latency_ms: 100, success: true, fallback_used: false, created_at: base)
        create_audit(latency_ms: 200, success: true, fallback_used: false, created_at: base + 1.second)
        create_audit(latency_ms: 300, success: true, fallback_used: true, created_at: base + 2.seconds)
        create_audit(latency_ms: 400, success: false, fallback_used: false, created_at: base + 3.seconds)
        create_audit(latency_ms: 500, success: true, tool_used: true, created_at: base + 4.seconds)
      end

      it 'aggregates total_requests' do
        m = described_class.call(time_window: '1h')
        expect(m[:total_requests]).to eq(5)
      end

      it 'computes p50 and p95 latency' do
        m = described_class.call(time_window: '1h')
        expect(m[:p50_latency_ms]).to eq(300)
        expect(m[:p95_latency_ms]).to eq(500)
      end

      it 'computes error_rate' do
        m = described_class.call(time_window: '1h')
        expect(m[:error_rate]).to be_within(0.001).of(1.0 / 5)
        expect(m[:error_count]).to eq(1)
      end

      it 'computes degraded_fallback_rate' do
        m = described_class.call(time_window: '1h')
        expect(m[:degraded_fallback_rate]).to be_within(0.001).of(1.0 / 5)
        expect(m[:degraded_fallback_count]).to eq(1)
      end

      it 'filters by merchant_id when provided' do
        other_merchant = create_merchant_with_api_key(name: 'Other').first
        AiRequestAudit.create!(
          request_id: SecureRandom.hex(8),
          endpoint: 'dashboard',
          agent_key: 'operational',
          merchant_id: other_merchant.id,
          created_at: 30.minutes.ago
        )
        m = described_class.call(time_window: '1h', merchant_id: merchant.id)
        expect(m[:total_requests]).to eq(5)
      end
    end

    context 'p50/p95 with single value' do
      before do
        create_audit(latency_ms: 1000, success: true, created_at: 30.minutes.ago)
      end

      it 'returns same value for p50 and p95' do
        m = described_class.call(time_window: '1h')
        expect(m[:p50_latency_ms]).to eq(1000)
        expect(m[:p95_latency_ms]).to eq(1000)
      end
    end
  end
end
