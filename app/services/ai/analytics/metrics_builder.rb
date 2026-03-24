# frozen_string_literal: true

module Ai
  module Analytics
    # Aggregates ai_request_audits into presentation-ready metrics.
    # No raw prompts, secrets, or cross-tenant exposure.
    class MetricsBuilder
      def self.call(scope)
        new(scope).call
      end

      def initialize(scope)
        @scope = scope
      end

      def call
        total = @scope.count
        return empty_metrics if total.zero?

        {
          summary: build_summary(total),
          by_agent: by_agent,
          by_composition_mode: by_composition_mode,
          tool_usage: tool_usage,
          skill_usage: skill_usage,
          fallback: fallback_metrics,
          policy: policy_metrics,
          followup: followup_metrics,
          latency: latency_metrics,
          citations: citation_metrics,
          memory: memory_metrics,
          recent_requests: recent_requests
        }
      end

      private

      def empty_metrics
        {
          summary: {
            total_requests: 0,
            avg_latency_ms: nil,
            fallback_rate: 0,
            tool_usage_rate: 0,
            policy_blocked_rate: 0,
            top_agent: nil
          },
          by_agent: [],
          by_composition_mode: [],
          tool_usage: {},
          skill_usage: {},
          fallback: {},
          policy: {},
          followup: {},
          latency: {},
          citations: {},
          memory: {},
          recent_requests: []
        }
      end

      def build_summary(total)
        avg = @scope.average(:latency_ms)
        fallback_count = @scope.where(fallback_used: true).count
        tool_count = @scope.where(tool_used: true).count
        policy_blocked = AiRequestAudit.column_names.include?('authorization_denied') ? @scope.where('authorization_denied = true OR tool_blocked_by_policy = true').count : 0
        top_agent = @scope.group(:agent_key).order('count_all DESC').limit(1).count.keys.first

        {
          total_requests: total,
          avg_latency_ms: avg&.round,
          fallback_rate: total.positive? ? (fallback_count.to_f / total).round(3) : 0,
          tool_usage_rate: total.positive? ? (tool_count.to_f / total).round(3) : 0,
          policy_blocked_rate: total.positive? ? (policy_blocked.to_f / total).round(3) : 0,
          top_agent: top_agent
        }
      end

      def by_agent
        @scope.group(:agent_key).order('count_all DESC').count
      end

      def by_composition_mode
        @scope.where.not(composition_mode: nil).group(:composition_mode).order('count_all DESC').count
      end

      def tool_usage
        total = @scope.count
        tool_count = @scope.where(tool_used: true).count
        tool_names = @scope.where(tool_used: true).pluck(:tool_names).flatten.compact
        freq = tool_names.tally.sort_by { |_, v| -v }.to_h
        {
          tool_used_count: tool_count,
          tool_usage_rate: total.positive? ? (tool_count.to_f / total).round(3) : 0,
          tool_names_frequency: freq
        }
      end

      def skill_usage
        return {} unless AiRequestAudit.column_names.include?('invoked_skills')

        total = @scope.count
        raw = @scope.pluck(:invoked_skills, :agent_key).compact.reject { |(inv, _)| inv.blank? || (inv.is_a?(Array) && inv.empty?) }
        all_skills = raw.flat_map { |(inv, _)| Array(inv).compact }
        return { skill_invoked_count: 0, skill_usage_rate: 0, skill_keys_frequency: {}, by_agent: {}, success_rate: nil } if all_skills.empty?

        invoked = all_skills.select { |s| s['invoked'] || s[:invoked] }
        failed = invoked.reject { |s| s['success'] || s[:success] }
        deterministic_count = invoked.count { |s| s['deterministic'] || s[:deterministic] }
        affected_count = all_skills.count { |s| s['affected_final_response'] || s[:affected_final_response] }
        skill_keys_freq = invoked.map { |s| s['skill_key'] || s[:skill_key] }.compact.tally.sort_by { |_, v| -v }.to_h
        by_agent = invoked.group_by { |s| s['agent_key'] || s[:agent_key] }.transform_values(&:size)

        # Profile-aware: avg skills per request by agent
        skills_per_request_by_agent = Hash.new { |h, k| h[k] = [] }
        raw.each do |inv, agent|
          agent_key = agent.to_s.presence || 'unknown'
          count = Array(inv).count { |s| s['invoked'] || s[:invoked] }
          skills_per_request_by_agent[agent_key] << count
        end
        avg_skills_per_request_by_agent = skills_per_request_by_agent.transform_values do |counts|
          counts.any? ? (counts.sum.to_f / counts.size).round(2) : 0
        end

        {
          skill_invoked_count: invoked.size,
          skill_usage_rate: total.positive? ? (raw.size.to_f / total).round(3) : 0,
          skill_keys_frequency: skill_keys_freq,
          by_agent: by_agent,
          avg_skills_per_request_by_agent: avg_skills_per_request_by_agent.presence,
          success_rate: invoked.any? ? (1 - failed.size.to_f / invoked.size).round(3) : nil,
          deterministic_rate: invoked.any? ? (deterministic_count.to_f / invoked.size).round(3) : nil,
          affected_response_count: affected_count
        }.compact
      end

      def fallback_metrics
        total = @scope.count
        fallback = @scope.where(fallback_used: true).count
        failed = @scope.where(success: false).count
        {
          fallback_count: fallback,
          fallback_rate: total.positive? ? (fallback.to_f / total).round(3) : 0,
          failed_count: failed,
          failed_rate: total.positive? ? (failed.to_f / total).round(3) : 0
        }
      end

      def policy_metrics
        total = @scope.count
        cols = AiRequestAudit.column_names
        auth_denied = cols.include?('authorization_denied') ? @scope.where(authorization_denied: true).count : 0
        tool_blocked = cols.include?('tool_blocked_by_policy') ? @scope.where(tool_blocked_by_policy: true).count : 0
        followup_blocked = cols.include?('followup_inheritance_blocked') ? @scope.where(followup_inheritance_blocked: true).count : 0
        policy_blocked = cols.include?('authorization_denied') ? @scope.where('authorization_denied = true OR tool_blocked_by_policy = true').count : 0
        {
          authorization_denied_count: auth_denied,
          tool_blocked_count: tool_blocked,
          followup_blocked_count: followup_blocked,
          policy_blocked_rate: total.positive? ? (policy_blocked.to_f / total).round(3) : 0
        }
      end

      def followup_metrics
        total = @scope.count
        followup = @scope.where(followup_detected: true).count
        by_type = @scope.where(followup_detected: true).group(:followup_type).order('count_all DESC').count
        {
          followup_count: followup,
          followup_rate: total.positive? ? (followup.to_f / total).round(3) : 0,
          by_type: by_type
        }
      end

      def latency_metrics
        avg = @scope.average(:latency_ms)
        by_agent = @scope.group(:agent_key).average(:latency_ms).transform_values { |v| v&.round }
        {
          avg_ms: avg&.round,
          by_agent: by_agent
        }
      end

      def citation_metrics
        total = @scope.count
        with_citations = @scope.where('citations_count > 0').count
        reask = @scope.where(citation_reask_used: true).count
        {
          with_citations_count: with_citations,
          with_citations_rate: total.positive? ? (with_citations.to_f / total).round(3) : 0,
          citation_reask_count: reask,
          citation_reask_rate: total.positive? ? (reask.to_f / total).round(3) : 0
        }
      end

      def memory_metrics
        total = @scope.count
        memory = @scope.where(memory_used: true).count
        summary = @scope.where(summary_used: true).count
        {
          memory_used_count: memory,
          memory_usage_rate: total.positive? ? (memory.to_f / total).round(3) : 0,
          summary_used_count: summary
        }
      end

      def recent_requests
        cols = AiRequestAudit.column_names
        has_policy = cols.include?('authorization_denied') && cols.include?('tool_blocked_by_policy')
        pluck_cols = %i[id created_at merchant_id agent_key composition_mode latency_ms success fallback_used
                        citations_count tool_used tool_names]
        pluck_cols += %i[authorization_denied tool_blocked_by_policy] if has_policy
        pluck_cols << :request_id
        @scope.order(created_at: :desc).limit(50).pluck(*pluck_cols).map do |row|
          req_id_idx = pluck_cols.size - 1
          policy_blocked = has_policy && !!(row[11] || row[12])
          {
            id: row[0],
            created_at: row[1],
            merchant_id: row[2],
            agent_key: row[3],
            composition_mode: row[4],
            latency_ms: row[5],
            success: row[6],
            fallback_used: row[7],
            citations_count: row[8],
            tool_used: row[9],
            tool_names: Array(row[10]).presence || [],
            policy_blocked: policy_blocked,
            request_id: row[req_id_idx]
          }
        end
      end
    end
  end
end
