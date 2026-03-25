# frozen_string_literal: true

module Ai
  module Skills
    module ValueAnalysis
      # Aggregates evidence-oriented metrics from `ai_request_audits` (production or any scope).
      # Does not claim causal business impact — only measurable signals: frequency, affected_final_response,
      # deterministic flags, workflows, and correlation with deterministic_explanation_used.
      class MetricCalculator
        # @param scope [ActiveRecord::Relation] typically `AiRequestAudit.where(...)` or `AiRequestAudit.all`
        def self.call(scope: AiRequestAudit.all)
          new(scope: scope).call
        end

        def initialize(scope:)
          @scope = scope
        end

        def call
          total = @scope.count
          return empty_result if total.zero?

          rows = @scope.pluck(
            :invoked_skills, :agent_key, :skill_workflow_metadata,
            :deterministic_explanation_used, :fallback_used, :tool_used
          )

          skill_rows = []
          workflow_keys = []
          requests_with_skill = 0
          requests_skill_affected = 0
          det_expl_with_any_skill = 0
          tool_with_any_skill = 0
          fallback_with_skill = 0
          requests_skill_and_det_expl = 0

          rows.each do |invoked, agent_key, wf_meta, det_expl, fallback, tool_used|
            inv = Array(invoked).compact
            has_invocation = inv.any? { |s| truthy?(s['invoked'] || s[:invoked]) }
            requests_with_skill += 1 if has_invocation
            requests_skill_affected += 1 if inv.any? { |s| truthy?(s['affected_final_response'] || s[:affected_final_response]) }
            det_expl_with_any_skill += 1 if truthy?(det_expl) && has_invocation
            tool_with_any_skill += 1 if truthy?(tool_used) && has_invocation
            fallback_with_skill += 1 if truthy?(fallback) && has_invocation
            skill_det = inv.any? { |s| truthy?(s['invoked'] || s[:invoked]) && truthy?(s['deterministic'] || s[:deterministic]) }
            requests_skill_and_det_expl += 1 if truthy?(det_expl) && has_invocation && skill_det

            inv.each do |s|
              next unless truthy?(s['invoked'] || s[:invoked])

              sk = (s['skill_key'] || s[:skill_key]).to_s.presence || 'unknown'
              skill_rows << {
                skill_key: sk,
                agent_key: (s['agent_key'] || s[:agent_key]).to_s.presence,
                deterministic: truthy?(s['deterministic'] || s[:deterministic]),
                affected: truthy?(s['affected_final_response'] || s[:affected_final_response]),
                success: skill_success?(s),
                audit_agent: agent_key.to_s.presence
              }
            end

            wk = extract_workflow_key(wf_meta)
            workflow_keys << wk if wk.present?
          end

          by_skill = tally_skill_metrics(skill_rows)
          by_audit_agent = tally_agent_intensity(rows)
          by_agent_and_skill = tally_agent_skill(skill_rows)
          wf_freq = workflow_keys.tally
          wf_total = workflow_keys.size

          invocations = skill_rows.size
          deterministic_invocations = skill_rows.count { |r| r[:deterministic] }
          affected_invocations = skill_rows.count { |r| r[:affected] }

          workflow_breakdown = build_workflow_breakdown(wf_freq, wf_total)

          {
            audit_sample_size: total,
            requests_with_any_skill: requests_with_skill,
            requests_with_any_skill_rate: round_rate(requests_with_skill, total),
            requests_with_skill_affected_response: requests_skill_affected,
            skill_affected_request_rate: round_rate(requests_skill_affected, total),
            skill_helpfulness_proxy: {
              invocation_affected_rate: round_rate(affected_invocations, invocations),
              request_affected_rate: round_rate(requests_skill_affected, requests_with_skill),
              note: 'Proxy for “skill changed outcome”: uses affected_final_response flags, not human ratings.'
            },
            fallback_with_skill_requests: fallback_with_skill,
            fallback_with_skill_rate_given_skill: round_rate(fallback_with_skill, requests_with_skill),
            deterministic_explanation_with_any_skill: det_expl_with_any_skill,
            deterministic_explanation_with_skill_rate: round_rate(det_expl_with_any_skill, requests_with_skill),
            deterministic_path_strengthened_requests: requests_skill_and_det_expl,
            deterministic_path_strengthened_rate: round_rate(requests_skill_and_det_expl, requests_with_skill),
            tool_used_with_any_skill: tool_with_any_skill,
            skill_invocation_total: invocations,
            skill_invocation_deterministic_count: deterministic_invocations,
            skill_invocation_deterministic_rate: round_rate(deterministic_invocations, invocations),
            skill_invocation_affected_count: affected_invocations,
            skill_invocation_affected_rate: round_rate(affected_invocations, invocations),
            by_skill: by_skill,
            workflow_audit_count: wf_total,
            workflow_selection_rate: round_rate(wf_total, requests_with_skill),
            workflow_key_frequency: wf_freq.sort_by { |_, v| -v }.to_h,
            workflow_breakdown: workflow_breakdown,
            by_audit_agent: by_audit_agent,
            skill_invocations_by_audit_agent: by_agent_and_skill,
            llm_dependency_proxy: {
              deterministic_skill_share_of_invocations: round_rate(deterministic_invocations, invocations),
              note: 'Higher deterministic share means more skill output is template/tool-backed rather than free-form.'
            }
          }
        end

        private

        def empty_result
          {
            audit_sample_size: 0,
            requests_with_any_skill: 0,
            requests_with_any_skill_rate: 0.0,
            requests_with_skill_affected_response: 0,
            skill_affected_request_rate: 0.0,
            skill_helpfulness_proxy: {
              invocation_affected_rate: 0.0,
              request_affected_rate: 0.0,
              note: 'No audit rows in scope.'
            },
            fallback_with_skill_requests: 0,
            fallback_with_skill_rate_given_skill: 0.0,
            deterministic_explanation_with_any_skill: 0,
            deterministic_explanation_with_skill_rate: 0.0,
            deterministic_path_strengthened_requests: 0,
            deterministic_path_strengthened_rate: 0.0,
            tool_used_with_any_skill: 0,
            skill_invocation_total: 0,
            skill_invocation_deterministic_count: 0,
            skill_invocation_deterministic_rate: 0.0,
            skill_invocation_affected_count: 0,
            skill_invocation_affected_rate: 0.0,
            by_skill: {},
            workflow_audit_count: 0,
            workflow_selection_rate: 0.0,
            workflow_key_frequency: {},
            workflow_breakdown: {},
            by_audit_agent: {},
            skill_invocations_by_audit_agent: {},
            llm_dependency_proxy: {
              deterministic_skill_share_of_invocations: nil,
              note: 'No audit rows in scope.'
            }
          }
        end

        def build_workflow_breakdown(wf_freq, wf_total)
          wf_string = (wf_freq || {}).transform_keys(&:to_s)
          Ai::Skills::Workflows::Registry.keys.each_with_object({}) do |key, h|
            ks = key.to_s
            c = wf_string[ks].to_i
            h[ks] = {
              audit_count: c,
              share_of_workflow_audits: wf_total.positive? ? round_rate(c, wf_total) : 0.0
            }
          end
        end

        def truthy?(v)
          v == true
        end

        def skill_success?(s)
          return true if s['success'] == true || s[:success] == true
          return false if s.key?('success') || s.key?(:success)

          nil
        end

        def extract_workflow_key(wf_meta)
          return nil if wf_meta.blank?

          h = wf_meta.is_a?(Hash) ? wf_meta.stringify_keys : {}
          (h['workflow_key'] || h[:workflow_key]).to_s.presence
        end

        def tally_skill_metrics(skill_rows)
          keys = skill_rows.map { |r| r[:skill_key] }.uniq.sort
          keys.each_with_object({}) do |sk, out|
            rows = skill_rows.select { |r| r[:skill_key] == sk }
            n = rows.size
            aff = rows.count { |r| r[:affected] }
            det = rows.count { |r| r[:deterministic] }
            succ = rows.count { |r| r[:success] != false }
            out[sk] = {
              invocation_count: n,
              affected_final_response_count: aff,
              affected_rate: round_rate(aff, n),
              deterministic_count: det,
              deterministic_rate: round_rate(det, n),
              success_count: succ,
              success_rate: round_rate(succ, n)
            }
          end
        end

        # Intensity: how many invocations per audit row (agent_key on audit row), not per-skill agent.
        def tally_agent_skill(skill_rows)
          skill_rows.group_by { |r| r[:audit_agent].presence || 'unknown' }.transform_values do |list|
            list.group_by { |r| r[:skill_key] }.transform_values(&:size).sort_by { |_, v| -v }.to_h
          end
        end

        def tally_agent_intensity(rows)
          counts = Hash.new { |h, k| h[k] = [] }
          rows.each do |invoked, agent_key, _wf, _det, _fb, _tool|
            inv = Array(invoked).compact
            n = inv.count { |s| truthy?(s['invoked'] || s[:invoked]) }
            ak = agent_key.to_s.presence || 'unknown'
            counts[ak] << n
          end
          counts.transform_values do |arr|
            next { request_count: 0, avg_invocations_per_request: 0.0, max_invocations: 0 } if arr.empty?

            {
              request_count: arr.size,
              avg_invocations_per_request: (arr.sum.to_f / arr.size).round(2),
              max_invocations: arr.max
            }
          end
        end

        def round_rate(num, den)
          return 0.0 if den.nil? || den.zero?

          (num.to_f / den).round(3)
        end
      end
    end
  end
end
