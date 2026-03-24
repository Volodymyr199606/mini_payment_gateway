# frozen_string_literal: true

module Ai
  module Evals
    module Skills
      # Wall-clock timing for skill-influenced paths (ScenarioRunner). For local / optional CI smoke.
      # Compares median ratios between two scenarios — never asserts absolute ms.
      class PerfComparison
        class << self
          # @param block [Proc] must return a value (e.g. ScenarioRunner.run_one result)
          # @return [Hash] { wall_seconds:, value: }
          def time_block
            t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            value = yield
            elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
            { wall_seconds: elapsed, value: value }
          end

          # Run block repeatedly; collect wall times
          def samples(iterations:, &block)
            return [] if iterations.to_i <= 0

            iterations.times.map { time_block(&block)[:wall_seconds] }
          end

          # @param max_ratio [Float] e.g. 25.0 — b median must not exceed a median * ratio
          def median_ratio_within?(samples_a, samples_b, max_ratio:)
            ma = MetricSamples.median(samples_a)
            mb = MetricSamples.median(samples_b)
            return false if ma.nil? || mb.nil? || ma <= 0.0

            (mb / ma) <= max_ratio.to_f
          end

          def report_hash(label_a:, samples_a:, label_b:, samples_b:)
            {
              label_a => MetricSamples.summarize(samples_a),
              label_b => MetricSamples.summarize(samples_b),
              median_ratio: MetricSamples.ratio(MetricSamples.median(samples_a), MetricSamples.median(samples_b))
            }
          end
        end
      end
    end
  end
end
