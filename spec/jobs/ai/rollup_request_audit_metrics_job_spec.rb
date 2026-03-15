# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::RollupRequestAuditMetricsJob, type: :job do
  include ActiveJob::TestHelper
  include ApiHelpers

  before do
    allow(Ai::Observability::EventLogger).to receive(:log_ai_job)
  end

  describe '#perform' do
    it 'builds metrics and writes summary to cache' do
      scope = double('scope')
      allow(Ai::Analytics::DashboardQuery).to receive(:call).with(time_preset: '7d').and_return(scope)
      allow(Ai::Analytics::MetricsBuilder).to receive(:call).with(scope).and_return(
        { summary: { total_requests: 1, by_agent: {} } }
      )
      allow(Rails.cache).to receive(:write).and_call_original

      perform_enqueued_jobs do
        described_class.perform_later(period: '7d')
      end

      expect(Ai::Analytics::DashboardQuery).to have_received(:call).with(time_preset: '7d')
      expect(Ai::Analytics::MetricsBuilder).to have_received(:call).with(scope)
      expect(Ai::Observability::EventLogger).to have_received(:log_ai_job).with(
        hash_including(phase: 'performed', job_class: 'Ai::RollupRequestAuditMetricsJob', period: '7d', total_requests: 1)
      )
      key = "ai:rollup:7d:#{Time.current.to_date}"
      expect(Rails.cache).to have_received(:write).with(key, { total_requests: 1, by_agent: {} }, expires_in: 1.hour)
    end

    it 'does not raise when no audits' do
      scope = double('scope')
      allow(Ai::Analytics::DashboardQuery).to receive(:call).with(time_preset: 'today').and_return(scope)
      allow(Ai::Analytics::MetricsBuilder).to receive(:call).with(scope).and_return(
        { summary: { total_requests: 0, by_agent: {} } }
      )

      perform_enqueued_jobs do
        described_class.perform_later(period: 'today')
      end
      expect(Ai::Observability::EventLogger).to have_received(:log_ai_job).with(hash_including(phase: 'performed'))
    end
  end
end
