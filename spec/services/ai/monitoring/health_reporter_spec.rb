# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Monitoring::HealthReporter do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }

  describe '.call' do
    context 'when no audit data' do
      it 'returns a HealthReport with healthy overall and empty metric_statuses for each window' do
        report = described_class.call(time_windows: %w[1h])
        expect(report).to be_a(Ai::Monitoring::HealthReport)
        expect(report.overall_status).to eq('healthy')
        expect(report.metric_statuses).to be_a(Array)
        expect(report.recent_anomalies).to eq([])
        expect(report.evaluated_at).to be_within(2).of(Time.current)
        expect(report.time_windows).to have_key('1h')
        expect(report.time_windows['1h'][:total_requests]).to eq(0)
      end

      it 'healthy? is true when overall is healthy' do
        report = described_class.call(time_windows: %w[1h])
        expect(report.healthy?).to be true
        expect(report.warning?).to be false
        expect(report.unhealthy?).to be false
      end
    end

    context 'when metrics breach SLO' do
      before do
        allow(Ai::Monitoring::SloConfig).to receive(:p95_latency_ms).and_return(100)
        AiRequestAudit.create!(
          request_id: SecureRandom.hex(8),
          endpoint: 'dashboard',
          agent_key: 'operational',
          merchant_id: merchant.id,
          latency_ms: 5000,
          success: true,
          created_at: Time.current
        )
      end

      it 'returns unhealthy overall when p95 above threshold' do
        report = described_class.call(time_windows: %w[1h])
        expect(report.overall_status).to eq('unhealthy')
        expect(report.unhealthy?).to be true
      end
    end

    it 'to_h returns serializable hash' do
      report = described_class.call(time_windows: %w[1h])
      h = report.to_h
      expect(h[:overall_status]).to eq('healthy')
      expect(h[:metric_statuses]).to be_a(Array)
      expect(h[:evaluated_at]).to be_present
      expect(h[:time_windows]).to be_a(Hash)
    end
  end
end
