# frozen_string_literal: true

require 'thread'

module MiniPaymentGatewayPerf
  class Runner
    GROUPS = {
      'payments' => %w[
        payment_create_intent
        payment_authorize
        payment_capture
        payment_refund_partial
        payment_list_intents
        payment_list_transactions
        payment_list_ledger
        payment_authorize_idempotent_warm
      ],
      'webhooks' => %w[
        webhook_inbound_signed
        webhook_inbound_duplicate
      ],
      'ai' => %w[
        ai_api_chat_operational
        ai_api_chat_same_message_cold_warm
        ai_dashboard_tool_orchestration
      ],
      'internal' => %w[
        dev_ai_health_json
      ]
    }.freeze

    class << self
      def require_perf!
        return if defined?(MiniPaymentGatewayPerf::Scenarios)

        perf_lib = Rails.root.join('perf', 'lib')
        $LOAD_PATH.unshift(perf_lib) unless $LOAD_PATH.include?(perf_lib.to_s)
        require 'mini_payment_gateway_perf/scenarios'
      end

      def run_all(iterations: nil, concurrency: nil, only: nil)
        iterations ||= ENV.fetch('PERF_ITERATIONS', '30').to_i
        concurrency ||= ENV.fetch('PERF_CONCURRENCY', '1').to_i
        only_list = only.presence || ENV['ONLY'].presence&.split(',')&.map(&:strip)
        list = if only_list.present?
                 Array(only_list)
               else
                 GROUPS.values.flatten.uniq
               end
        run_scenarios(list, iterations: iterations, concurrency: concurrency)
      end

      def run_group(name, iterations: nil, concurrency: nil)
        scenarios = GROUPS[name.to_s] || raise(ArgumentError, "Unknown perf group: #{name}. Known: #{GROUPS.keys.join(', ')}")
        iterations ||= ENV.fetch('PERF_ITERATIONS', '30').to_i
        concurrency ||= ENV.fetch('PERF_CONCURRENCY', '1').to_i
        run_scenarios(scenarios, iterations: iterations, concurrency: concurrency)
      end

      def run_scenarios(names, iterations:, concurrency:)
        Stubs.install!
        report = Report.new(
          'rails_env' => Rails.env,
          'iterations' => iterations,
          'concurrency' => concurrency,
          'pid' => Process.pid
        )

        names.each do |scenario_name|
          fn = Scenarios.registry[scenario_name]
          raise "Unknown scenario: #{scenario_name}" unless fn

          row = fn.call(iterations: iterations, concurrency: concurrency)
          row[:scenario] = scenario_name
          report.add_scenario(row)
          puts format_row(row)
        end

        paths = report.write!
        puts "\nWrote:\n  #{paths[:json]}\n  #{paths[:markdown]}"
        paths
      end

      def format_row(row)
        format(
          '%<scenario>-40s runs=%<runs>3d err=%<errors>3d med=%<median_ms>8s p95=%<p95_ms>8s rps=%<throughput_rps>s %<notes>s',
          scenario: row[:scenario],
          runs: row[:runs],
          errors: row[:errors],
          median_ms: row[:median_ms].inspect,
          p95_ms: row[:p95_ms].inspect,
          throughput_rps: row[:throughput_rps].inspect,
          notes: row[:notes].to_s[0, 50]
        )
      end

      # Run block `iterations` times; each invocation receives [harness, world].
      # With concurrency > 1, work is split across threads (each thread has its own world + harness).
      def measure(iterations:, concurrency:, cache_state: nil, notes: nil, prepare: nil)
        latencies = []
        errors = 0
        mtx = Mutex.new
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        record = lambda do |harness, world|
          ms, err = timed_ms { yield harness, world }
          mtx.synchronize do
            if err
              errors += 1
            else
              latencies << ms
            end
          end
        end

        if concurrency <= 1
          world = World.build!
          harness = Harness.new
          prepare&.call(harness, world)
          iterations.times { record.call(harness, world) }
        else
          q = Queue.new
          iterations.times { |i| q.push(i) }
          threads = Array.new(concurrency) do
            Thread.new do
              w = World.build!
              h = Harness.new
              prepare&.call(h, w)
              loop do
                q.pop(true)
                record.call(h, w)
              end
            rescue ThreadError
              # queue empty
            end
          end
          threads.each(&:join)
        end

        t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        summary = Metrics.summarize(latencies)
        merged = Metrics.merge_timing(summary, errors: errors, duration_sec: t1 - t0)
        {
          cache_state: cache_state,
          notes: notes
        }.merge(merged)
      end

      def timed_ms
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        err = false
        begin
          yield
        rescue StandardError => e
          warn "[perf] #{e.class}: #{e.message}"
          err = true
        end
        t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        [((t1 - t0) * 1000).round(3), err]
      end
    end
  end
end
