# frozen_string_literal: true

# Local load/perf scenarios (deterministic stubs; no external Groq/processor).
# See docs/LOAD_AND_PERFORMANCE_TESTING.md

perf_lib = Rails.root.join('perf', 'lib')
$LOAD_PATH.unshift(perf_lib.to_s) unless $LOAD_PATH.include?(perf_lib.to_s)

namespace :perf do
  desc 'Run all perf scenarios (ENV: PERF_ITERATIONS=30 PERF_CONCURRENCY=1 ONLY=name,name2)'
  task run: :environment do
    require 'mini_payment_gateway_perf'
    MiniPaymentGatewayPerf::Runner.run_all
  end

  desc 'Payment API + dashboard list scenarios'
  task payments: :environment do
    require 'mini_payment_gateway_perf'
    MiniPaymentGatewayPerf::Runner.run_group('payments')
  end

  desc 'Webhook ingest scenarios'
  task webhooks: :environment do
    require 'mini_payment_gateway_perf'
    MiniPaymentGatewayPerf::Runner.run_group('webhooks')
  end

  desc 'AI API + dashboard scenarios (Groq stubbed)'
  task ai: :environment do
    require 'mini_payment_gateway_perf'
    MiniPaymentGatewayPerf::Runner.run_group('ai')
  end

  desc 'Internal dev routes (health JSON); dev/test only'
  task internal: :environment do
    require 'mini_payment_gateway_perf'
    MiniPaymentGatewayPerf::Runner.run_group('internal')
  end
end
