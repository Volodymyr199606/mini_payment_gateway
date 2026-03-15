# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Monitoring::SloEvaluator do
  describe '.call' do
    it 'returns healthy statuses when metrics within thresholds' do
      metrics = {
        p95_latency_ms: 5000,
        error_rate: 0.02,
        degraded_fallback_rate: 0.05,
        retrieval_failure_rate: 0.05,
        policy_blocked_rate: 0.02,
        citation_reask_rate: 0.05,
        orchestration_usage_rate: 0.1,
        orchestration_failure_rate: 0.0
      }
      statuses = described_class.call(metrics, time_window: '1h')
      expect(statuses.size).to be >= 5
      unhealthy = statuses.select { |s| s.status == 'unhealthy' }
      expect(unhealthy).to be_empty
    end

    it 'returns unhealthy for p95 above threshold' do
      allow(Ai::Monitoring::SloConfig).to receive(:p95_latency_ms).and_return(1000)
      metrics = {
        p95_latency_ms: 2000,
        error_rate: 0,
        degraded_fallback_rate: 0,
        retrieval_failure_rate: 0,
        policy_blocked_rate: 0,
        citation_reask_rate: 0,
        orchestration_usage_rate: 0,
        orchestration_failure_rate: 0
      }
      statuses = described_class.call(metrics, time_window: '1h')
      p95_status = statuses.find { |s| s.metric_name == 'p95_latency_ms' }
      expect(p95_status.status).to eq('unhealthy')
      expect(p95_status.reason_code).to eq('p95_above_threshold')
    end

    it 'returns unhealthy for error_rate above threshold' do
      allow(Ai::Monitoring::SloConfig).to receive(:error_rate_max).and_return(0.05)
      metrics = {
        p95_latency_ms: 500,
        error_rate: 0.10,
        degraded_fallback_rate: 0,
        retrieval_failure_rate: 0,
        policy_blocked_rate: 0,
        citation_reask_rate: 0,
        orchestration_usage_rate: 0,
        orchestration_failure_rate: 0
      }
      statuses = described_class.call(metrics, time_window: '1h')
      err_status = statuses.find { |s| s.metric_name == 'error_rate' }
      expect(err_status.status).to eq('unhealthy')
    end

    it 'returns warning for degraded_fallback_rate above threshold' do
      allow(Ai::Monitoring::SloConfig).to receive(:degraded_fallback_rate_max).and_return(0.10)
      metrics = {
        p95_latency_ms: 500,
        error_rate: 0,
        degraded_fallback_rate: 0.20,
        retrieval_failure_rate: 0,
        policy_blocked_rate: 0,
        citation_reask_rate: 0,
        orchestration_usage_rate: 0,
        orchestration_failure_rate: 0
      }
      statuses = described_class.call(metrics, time_window: '1h')
      fb_status = statuses.find { |s| s.metric_name == 'degraded_fallback_rate' }
      expect(fb_status.status).to eq('warning')
    end
  end
end
