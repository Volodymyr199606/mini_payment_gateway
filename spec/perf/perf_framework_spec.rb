# frozen_string_literal: true

require 'rails_helper'

perf_lib = Rails.root.join('perf', 'lib').to_s
$LOAD_PATH.unshift(perf_lib) unless $LOAD_PATH.include?(perf_lib)
require 'mini_payment_gateway_perf'

# Validates perf harness wiring and output shape — not machine-specific latencies.
RSpec.describe 'MiniPaymentGatewayPerf framework' do
  describe MiniPaymentGatewayPerf::Metrics do
    it 'summarizes latency samples' do
      s = described_class.summarize([10.0, 20.0, 30.0, 40.0])
      expect(s[:runs]).to eq(4)
      # Nearest-rank p50 (see Metrics.percentile): n=4 → rank 2 → 20.0
      expect(s[:median_ms]).to eq(20.0)
      expect(s[:min_ms]).to eq(10.0)
      expect(s[:max_ms]).to eq(40.0)
      expect(s[:p95_ms]).to be_a(Numeric)
    end

    it 'returns empty summary for no samples' do
      s = described_class.summarize([])
      expect(s[:runs]).to eq(0)
      expect(s[:median_ms]).to be_nil
    end

    it 'merges error counts and throughput' do
      base = described_class.summarize([100.0, 200.0])
      m = described_class.merge_timing(base, errors: 1, duration_sec: 2.0)
      expect(m[:errors]).to eq(1)
      expect(m[:throughput_rps]).to eq(1.0)
      expect(m[:duration_sec]).to eq(2.0)
    end
  end

  describe 'Runner::GROUPS and Scenarios.registry' do
    it 'registers every scenario listed in GROUPS' do
      names = MiniPaymentGatewayPerf::Runner::GROUPS.values.flatten.uniq
      reg = MiniPaymentGatewayPerf::Scenarios.registry
      expect(names).to all(be_in(reg.keys)),
                      "missing registry entries: #{names - reg.keys}"
    end

    it 'does not define orphan scenario keys outside GROUPS' do
      allowed = MiniPaymentGatewayPerf::Runner::GROUPS.values.flatten.to_set
      MiniPaymentGatewayPerf::Scenarios.registry.each_key do |key|
        expect(allowed).to include(key), "orphan scenario key #{key.inspect}"
      end
    end

    it 'defines perf tasks in lib/tasks/perf.rake' do
      src = Rails.root.join('lib/tasks/perf.rake').read
      expect(src).to include('namespace :perf')
      expect(src).to include("task run:")
      expect(src).to include("run_group('payments')", "run_group('webhooks')", "run_group('ai')", "run_group('internal')")
    end
  end

  describe MiniPaymentGatewayPerf::Runner do
    describe '.timed_ms' do
      it 'returns error flag when the block raises' do
        ms, err = described_class.timed_ms { raise StandardError, 'expected' }
        expect(err).to be true
        expect(ms).to be >= 0
      end

      it 'returns error false on success' do
        _ms, err = described_class.timed_ms { :ok }
        expect(err).to be false
      end
    end
  end

  describe MiniPaymentGatewayPerf::Report do
    it 'writes JSON and Markdown with expected top-level keys' do
      Dir.mktmpdir do |dir|
        report = described_class.new('rails_env' => 'test', 'iterations' => 1, 'concurrency' => 1)
        report.add_scenario(
          'scenario' => 'fixture_scenario',
          'runs' => 3,
          'errors' => 0,
          'min_ms' => 1.0,
          'max_ms' => 3.0,
          'mean_ms' => 2.0,
          'median_ms' => 2.0,
          'p95_ms' => 3.0,
          'duration_sec' => 1.0,
          'throughput_rps' => 3.0,
          'cache_state' => 'none',
          'notes' => 'fixture'
        )
        paths = report.write!(root: Pathname(dir))
        payload = JSON.parse(File.read(paths[:json]))
        expect(payload).to include('recorded_at', 'meta', 'scenarios')
        expect(payload['meta']).to include('rails_env' => 'test')
        expect(payload['scenarios'].first).to include('scenario' => 'fixture_scenario')
        md = File.read(paths[:markdown])
        expect(md).to include('fixture_scenario')
        expect(md).to include('|')
      end
    end
  end

  describe MiniPaymentGatewayPerf::Scenarios do
    describe '.webhook_payload' do
      it 'builds JSON and a signature verifiable by DeterministicProvider' do
        body, sig = described_class.webhook_payload(merchant_id: 42, event_id: 'evt_fixture')
        expect(body).to include('transaction.succeeded')
        provider = MiniPaymentGatewayPerf::Stubs::DeterministicProvider.new
        headers = { 'HTTP_X_WEBHOOK_SIGNATURE' => sig }
        expect(provider.verify_webhook_signature(payload: body, headers: headers)).to be true
      end
    end
  end
end
