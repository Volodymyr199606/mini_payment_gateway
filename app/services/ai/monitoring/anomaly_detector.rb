# frozen_string_literal: true

module Ai
  module Monitoring
    # Simple anomaly detection from recent ai_request_audits: high latency,
    # elevated fallback/error/policy blocks. No full incident system.
    class AnomalyDetector
      BUCKET_MINUTES = 60
      LOOKBACK_BUCKETS = 24
      HIGH_LATENCY_MS = 15_000
      HIGH_ERROR_RATE = 0.15
      HIGH_FALLBACK_RATE = 0.25
      HIGH_POLICY_RATE = 0.15

      def self.call(merchant_id: nil)
        new(merchant_id: merchant_id).call
      end

      def initialize(merchant_id: nil)
        @merchant_id = merchant_id.presence
      end

      def call
        anomalies = []
        # `N * (minutes.ago)` produces `TimeWithZone * Integer` which crashes.
        # We want a single timestamp `LOOKBACK_BUCKETS * BUCKET_MINUTES` minutes ago.
        since = (LOOKBACK_BUCKETS * BUCKET_MINUTES).minutes.ago
        scope = AiRequestAudit.where(created_at: since..Time.current)
        scope = scope.where(merchant_id: @merchant_id) if @merchant_id.present?

        # High latency: requests over threshold in last 24h
        high_latency = scope.where('latency_ms > ?', HIGH_LATENCY_MS).order(created_at: :desc).limit(20)
        if high_latency.any?
          anomalies << {
            type: 'high_latency',
            description: "#{high_latency.count} requests with latency > #{HIGH_LATENCY_MS}ms",
            count: high_latency.count,
            sample_request_ids: high_latency.limit(5).pluck(:request_id),
            window: '24h'
          }
        end

        # Elevated error rate in last 1h
        one_hour_scope = scope.where(created_at: 1.hour.ago..Time.current)
        total_1h = one_hour_scope.count
        if total_1h >= 5
          err_count = one_hour_scope.where(success: false).count
          err_rate = err_count.to_f / total_1h
          if err_rate >= HIGH_ERROR_RATE
            anomalies << {
              type: 'elevated_error_rate',
              description: "Error rate #{((err_rate) * 100).round(1)}% in last hour",
              count: err_count,
              total: total_1h,
              rate: err_rate.round(4),
              window: '1h'
            }
          end
        end

        # Elevated fallback rate in last 1h
        if total_1h >= 5
          fallback_count = one_hour_scope.where(fallback_used: true).count
          fallback_rate = fallback_count.to_f / total_1h
          if fallback_rate >= HIGH_FALLBACK_RATE
            anomalies << {
              type: 'elevated_fallback_rate',
              description: "Fallback rate #{((fallback_rate) * 100).round(1)}% in last hour",
              count: fallback_count,
              total: total_1h,
              rate: fallback_rate.round(4),
              window: '1h'
            }
          end
        end

        # Policy block spike (if column exists)
        if total_1h >= 5 && AiRequestAudit.column_names.include?('authorization_denied')
          policy_count = one_hour_scope.where('authorization_denied = true OR tool_blocked_by_policy = true').count
          policy_rate = policy_count.to_f / total_1h
          if policy_rate >= HIGH_POLICY_RATE
            anomalies << {
              type: 'policy_block_spike',
              description: "Policy blocked rate #{((policy_rate) * 100).round(1)}% in last hour",
              count: policy_count,
              total: total_1h,
              rate: policy_rate.round(4),
              window: '1h'
            }
          end
        end

        anomalies
      end
    end
  end
end
