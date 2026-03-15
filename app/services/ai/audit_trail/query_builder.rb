# frozen_string_literal: true

module Ai
  module AuditTrail
    # Builds safe filtered queries for ai_request_audits. Internal/dev use only.
    # Only filters on persisted columns; no raw SQL injection.
    class QueryBuilder
      DEFAULT_LIMIT = 100
      HIGH_LATENCY_MS = 5000

      def self.call(params: {}, limit: DEFAULT_LIMIT)
        new(params: params, limit: limit).call
      end

      def initialize(params: {}, limit: DEFAULT_LIMIT)
        @params = params.to_h.with_indifferent_access
        @limit = limit.to_i.clamp(1, 500)
      end

      def call
        rel = AiRequestAudit.recent
        rel = apply_time_range(rel)
        rel = apply_merchant(rel)
        rel = apply_agent_key(rel)
        rel = apply_composition_mode(rel)
        rel = apply_degraded_only(rel)
        rel = apply_fallback_only(rel)
        rel = apply_policy_blocked_only(rel)
        rel = apply_tool_used(rel)
        rel = apply_request_id(rel)
        rel = apply_failed_only(rel)
        rel = apply_high_latency_only(rel)
        rel = apply_min_latency(rel)
        rel.limit(@limit)
      end

      private

      def columns
        @columns ||= AiRequestAudit.column_names.map(&:to_s).freeze
      end

      def apply_time_range(rel)
        from = @params[:from].presence
        to = @params[:to].presence
        return rel unless from || to

        from_time = parse_time(from)
        to_time = parse_time(to)
        return rel unless from_time || to_time

        scope = rel
        scope = scope.where('created_at >= ?', from_time) if from_time
        scope = scope.where('created_at <= ?', to_time) if to_time
        scope
      end

      def parse_time(str)
        return nil unless str.present?

        Time.zone.parse(str.to_s)
      rescue ArgumentError
        nil
      end

      def apply_merchant(rel)
        return rel unless columns.include?('merchant_id')

        mid = @params[:merchant_id].presence
        return rel unless mid

        rel.where(merchant_id: mid)
      end

      def apply_agent_key(rel)
        key = @params[:agent_key].presence
        return rel unless key

        rel.where(agent_key: key)
      end

      def apply_composition_mode(rel)
        return rel unless columns.include?('composition_mode')

        mode = @params[:composition_mode].presence
        return rel unless mode

        rel.where(composition_mode: mode)
      end

      def apply_degraded_only(rel)
        return rel unless @params[:degraded_only].to_s.in?(%w[1 true])

        return rel unless columns.include?('degraded')
        rel.where(degraded: true)
      end

      def apply_fallback_only(rel)
        return rel unless @params[:fallback_only].to_s.in?(%w[1 true])

        rel.where(fallback_used: true)
      end

      def apply_policy_blocked_only(rel)
        return rel unless @params[:policy_blocked_only].to_s.in?(%w[1 true])

        if columns.include?('authorization_denied') && columns.include?('tool_blocked_by_policy')
          rel.where('authorization_denied = true OR tool_blocked_by_policy = true')
        else
          rel.none
        end
      end

      def apply_tool_used(rel)
        val = @params[:tool_used].presence
        return rel unless val

        if val.to_s.in?(%w[1 true yes])
          rel.where(tool_used: true)
        elsif val.to_s.in?(%w[0 false no])
          rel.where(tool_used: false)
        else
          # Filter by tool name (tool_names is jsonb array)
          rel.where(tool_used: true).where('tool_names @> ?', [val.to_s].to_json)
        end
      end

      def apply_request_id(rel)
        q = @params[:request_id].to_s.strip.presence
        return rel unless q

        rel.where('request_id ILIKE ?', "%#{AiRequestAudit.sanitize_sql_like(q)}%")
      end

      def apply_failed_only(rel)
        return rel unless @params[:failed_only].to_s.in?(%w[1 true])

        rel.where(success: false)
      end

      def apply_high_latency_only(rel)
        return rel unless @params[:high_latency_only].to_s.in?(%w[1 true])
        return rel unless columns.include?('latency_ms')

        min = @params[:min_latency_ms].presence
        threshold = min.to_i.positive? ? min.to_i : HIGH_LATENCY_MS
        rel.where('latency_ms IS NOT NULL AND latency_ms >= ?', threshold)
      end

      def apply_min_latency(rel)
        return rel unless columns.include?('latency_ms')

        min = @params[:min_latency_ms].presence
        return rel if min.blank? || min.to_i <= 0

        rel.where('latency_ms IS NOT NULL AND latency_ms >= ?', min.to_i)
      end
    end
  end
end
