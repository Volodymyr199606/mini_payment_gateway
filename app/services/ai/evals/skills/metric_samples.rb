# frozen_string_literal: true

module Ai
  module Evals
    module Skills
      # Deterministic statistics over numeric samples (no external deps).
      # Used for perf comparison and reports — not for asserting machine-specific absolute latency in CI.
      module MetricSamples
        class << self
          def percentile(sorted_samples, p)
            return nil if sorted_samples.blank?

            arr = sorted_samples.sort
            return arr.first if arr.size == 1

            idx = (p / 100.0) * (arr.size - 1)
            lo = idx.floor
            hi = idx.ceil
            return arr[lo] if lo == hi

            frac = idx - lo
            arr[lo] + frac * (arr[hi] - arr[lo])
          end

          def median(samples)
            percentile(samples, 50)
          end

          def p95(samples)
            percentile(samples, 95)
          end

          # @return [Hash] summary for reporting
          def summarize(samples)
            s = Array(samples).map(&:to_f)
            return { count: 0, median: nil, p95: nil, min: nil, max: nil } if s.empty?

            sorted = s.sort
            {
              count: sorted.size,
              median: median(sorted),
              p95: p95(sorted),
              min: sorted.first,
              max: sorted.last
            }
          end

          # Relative ratio (b / a), guards zero/NaN
          def ratio(a, b)
            return nil if a.nil? || b.nil?
            return nil if a.to_f <= 0.0

            b.to_f / a.to_f
          end
        end
      end
    end
  end
end
