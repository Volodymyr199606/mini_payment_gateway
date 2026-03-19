# frozen_string_literal: true

module MiniPaymentGatewayPerf
  # Pure-Ruby latency stats (no Rails dependency) for reporting and unit tests.
  module Metrics
    module_function

    # Nearest-rank percentile (same idea as common p95 definitions).
    def percentile(sorted_samples, p)
      return nil if sorted_samples.blank?

      arr = sorted_samples.sort
      n = arr.length
      return arr.first if n == 1

      rank = ((p.to_f / 100.0) * n).ceil.clamp(1, n)
      arr[rank - 1]
    end

    def summarize(latency_ms_array)
      samples = latency_ms_array.map(&:to_f).reject(&:negative?)
      return empty_summary if samples.empty?

      sorted = samples.sort
      n = sorted.size
      sum = sorted.sum
      {
        runs: n,
        success: n, # caller merges errors separately
        errors: 0,
        min_ms: sorted.first.round(3),
        max_ms: sorted.last.round(3),
        mean_ms: (sum / n).round(3),
        median_ms: percentile(sorted, 50).round(3),
        p95_ms: percentile(sorted, 95).round(3)
      }
    end

    def empty_summary
      {
        runs: 0,
        success: 0,
        errors: 0,
        min_ms: nil,
        max_ms: nil,
        mean_ms: nil,
        median_ms: nil,
        p95_ms: nil
      }
    end

    def merge_timing(summary, errors:, duration_sec:)
      s = summary.dup
      s[:errors] = errors
      s[:duration_sec] = duration_sec.round(3)
      if s[:runs].positive? && duration_sec.positive?
        s[:throughput_rps] = (s[:runs].to_f / duration_sec).round(3)
      else
        s[:throughput_rps] = nil
      end
      s
    end
  end
end
