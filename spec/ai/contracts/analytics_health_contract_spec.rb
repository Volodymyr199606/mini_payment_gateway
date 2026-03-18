# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Analytics and health result contracts' do
  describe 'MetricsBuilder (analytics) output' do
    it 'empty_metrics has stable top-level keys' do
      scope = AiRequestAudit.none
      metrics = Ai::Analytics::MetricsBuilder.call(scope)
      expected_keys = %i[summary by_agent by_composition_mode tool_usage fallback policy followup latency citations memory recent_requests]
      expected_keys.each do |k|
        expect(metrics).to have_key(k), "MetricsBuilder empty_metrics must have key #{k}"
      end
      expect(metrics[:summary]).to be_a(Hash)
      expect(metrics[:summary]).to have_key(:total_requests)
      expect(metrics[:summary]).to have_key(:fallback_rate)
      expect(metrics[:summary]).to have_key(:tool_usage_rate)
      expect(metrics[:summary]).to have_key(:policy_blocked_rate)
    end

    it 'summary has numeric or nil values for rates' do
      scope = AiRequestAudit.none
      metrics = Ai::Analytics::MetricsBuilder.call(scope)
      summary = metrics[:summary]
      expect(summary[:total_requests]).to be_a(Integer)
      expect(summary[:fallback_rate]).to be_a(Numeric)
      expect(summary[:tool_usage_rate]).to be_a(Numeric)
    end
  end

  describe 'HealthReport contract' do
    it 'to_h includes overall_status and allowed values are healthy/warning/unhealthy' do
      report = Ai::Monitoring::HealthReport.new(
        overall_status: 'healthy',
        metric_statuses: [],
        recent_anomalies: [],
        evaluated_at: Time.current,
        time_windows: {}
      )
      h = report.to_h
      expect(h).to have_key(:overall_status)
      expect(%w[healthy warning unhealthy]).to include(h[:overall_status])
      expect(h).to have_key(:metric_statuses)
      expect(h).to have_key(:evaluated_at)
      expect(h).to have_key(:time_windows)
    end

    it 'metric_status has status and metric_name when present' do
      status = Ai::Monitoring::MetricStatus.healthy(metric_name: 'p95_latency_ms', value: 100, time_window: '15m', threshold: 5000)
      h = status.to_h
      expect(h).to have_key(:status)
      expect(%w[healthy warning unhealthy]).to include(h[:status])
      expect(h).to have_key(:metric_name)
    end
  end
end
