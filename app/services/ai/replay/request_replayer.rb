# frozen_string_literal: true

module Ai
  module Replay
    # Reruns a historical AI request through the current pipeline and compares outcome.
    # Internal/dev only. Uses only safe persisted audit data; no prompts or secrets.
    class RequestReplayer
      def self.call(audit_id:, request_id: nil)
        new(audit_id: audit_id, request_id: request_id).call
      end

      def initialize(audit_id:, request_id: nil)
        @audit_id = audit_id
        @request_id = request_id.to_s.presence || "replay-#{audit_id}-#{SecureRandom.hex(4)}"
      end

      def call
        audit = AiRequestAudit.find_by(id: @audit_id)
        unless audit
          return ReplayResult.new(
            replay_possible: false,
            reason_codes: ['audit_not_found'],
            notes: ['Audit record not found.']
          )
        end

        input = ReplayInputBuilder.call(audit)
        unless input.possible?
          log_replay(audit_id: @audit_id, replay_possible: false, reason: input.reason_code)
          return ReplayResult.new(
            original_audit_id: @audit_id,
            replay_possible: false,
            original_summary: summary_from_audit(audit),
            reason_codes: [input.reason_code],
            notes: ['Replay not possible: insufficient safe input (e.g. non-tool path or missing merchant).']
          )
        end

        run_replay(audit, input)
      rescue StandardError => e
        log_replay(audit_id: @audit_id, replay_possible: true, failure: e.message)
        ReplayResult.new(
          original_audit_id: @audit_id,
          replay_possible: true,
          original_summary: audit ? summary_from_audit(audit) : {},
          replay_failure: e.message,
          reason_codes: ['replay_error'],
          notes: ["Replay failed: #{e.message}"]
        )
      end

      private

      def run_replay(audit, input)
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        run_result = ::Ai::Orchestration::ConstrainedRunner.call(
          message: input.message,
          merchant_id: input.merchant_id,
          request_id: @request_id,
          resolved_intent: input.resolved_intent
        )

        skill_outcome = if run_result.orchestration_used? && run_result.tool_names.any?
          agent_key = run_result.step_count > 1 ? 'orchestration' : "tool:#{run_result.tool_names.first}"
          ::Ai::Skills::InvocationCoordinator.post_tool(
            agent_key: agent_key,
            merchant_id: input.merchant_id,
            message: input.message,
            tool_names: run_result.tool_names.to_a,
            deterministic_data: run_result.deterministic_data,
            run_result: run_result,
            intent: input.resolved_intent
          )
        end

        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
        original_summary = summary_from_audit(audit)
        replay_summary = summary_from_run(run_result, skill_outcome)

        differences = DiffBuilder.call(original_summary: original_summary, replay_summary: replay_summary)
        matched = DiffBuilder.matched_flags(original_summary: original_summary, replay_summary: replay_summary)

        log_replay(
          audit_id: @audit_id,
          replay_possible: true,
          duration_ms: duration_ms,
          diff_summary: differences.size
        )

        ReplayResult.new(
          original_audit_id: @audit_id,
          replay_possible: true,
          replay_mode_used: true,
          original_summary: original_summary,
          replay_summary: replay_summary,
          differences: differences,
          duration_ms: duration_ms,
          reason_codes: [input.reason_code],
          notes: input.reason_code == 'intent_replay' ? ['Replay used reconstructed intent from audit.'] : [],
          **matched
        )
      end

      def summary_from_audit(audit)
        {
          agent_key: audit.agent_key,
          composition_mode: audit.composition_mode,
          tool_used: audit.tool_used?,
          tool_names: Array(audit.tool_names),
          orchestration_used: audit.try(:orchestration_used),
          orchestration_step_count: audit.try(:orchestration_step_count),
          citations_count: audit.citations_count.to_i,
          retrieved_sections_count: audit.retrieved_sections_count,
          fallback_used: audit.fallback_used?,
          memory_used: audit.memory_used?,
          success: audit.success?,
          authorization_denied: audit.try(:authorization_denied),
          tool_blocked_by_policy: audit.try(:tool_blocked_by_policy),
          deterministic_explanation_used: audit.try(:deterministic_explanation_used),
          explanation_type: audit.try(:explanation_type),
          explanation_key: audit.try(:explanation_key),
          execution_mode: audit.try(:execution_mode),
          retrieval_skipped: audit.try(:retrieval_skipped),
          memory_skipped: audit.try(:memory_skipped),
          degraded: audit.try(:degraded),
          fallback_mode: audit.try(:fallback_mode),
          latency_ms: audit.latency_ms,
          invoked_skills: skill_usage_from_audit(audit),
          skill_keys: skill_keys_from_audit(audit)
        }.compact
      end

      def summary_from_run(run_result, skill_outcome = nil)
        agent_key = run_result.step_count > 1 ? 'orchestration' : "tool:#{run_result.tool_names.first}"
        invoked_skills = skill_usage_from_outcome(skill_outcome, agent_key)
        base = {
          agent_key: agent_key,
          composition_mode: 'tool_only',
          tool_used: run_result.tool_names.any?,
          tool_names: run_result.tool_names.to_a,
          orchestration_used: run_result.orchestration_used?,
          orchestration_step_count: run_result.step_count,
          citations_count: 0,
          retrieved_sections_count: nil,
          fallback_used: false,
          memory_used: false,
          success: run_result.success?,
          authorization_denied: run_result.metadata[:authorization_denied],
          tool_blocked_by_policy: run_result.metadata[:tool_blocked_by_policy],
          deterministic_explanation_used: run_result.explanation_metadata&.dig(:deterministic_explanation_used),
          explanation_type: run_result.explanation_metadata&.dig(:explanation_type),
          explanation_key: run_result.explanation_metadata&.dig(:explanation_key),
          execution_mode: 'deterministic_only',
          retrieval_skipped: true,
          memory_skipped: true,
          degraded: false,
          fallback_mode: nil,
          latency_ms: run_result.metadata[:latency_ms]
        }
        base[:invoked_skills] = invoked_skills if invoked_skills.present?
        base[:skill_keys] = invoked_skills.map { |s| s['skill_key'] || s[:skill_key] }.compact.uniq if invoked_skills.present?
        base.compact
      end

      def skill_usage_from_audit(audit)
        return nil unless audit.respond_to?(:invoked_skills)
        raw = audit.invoked_skills
        return nil if raw.blank?
        ::Ai::Skills::UsageSerializer.normalize(raw: raw)
      end

      def skill_keys_from_audit(audit)
        usage = skill_usage_from_audit(audit)
        return nil if usage.blank?
        usage.map { |s| s['skill_key'] || s[:skill_key] }.compact.uniq.sort
      end

      def skill_usage_from_outcome(skill_outcome, agent_key)
        return [] if skill_outcome.blank? || !skill_outcome[:invocation_results].present?
        ::Ai::Skills::UsageSerializer.normalize(
          raw: skill_outcome[:invocation_results],
          agent_key: agent_key,
          affected_final_response: skill_outcome[:skill_affected_reply]
        )
      end

      def log_replay(audit_id:, replay_possible:, duration_ms: nil, diff_summary: nil, reason: nil, failure: nil)
        payload = {
          event: :ai_replay,
          original_audit_id: audit_id,
          replay_possible: replay_possible,
          request_id: @request_id
        }
        payload[:duration_ms] = duration_ms if duration_ms
        payload[:diff_summary] = diff_summary if diff_summary
        payload[:reason_code] = reason if reason
        payload[:replay_failure] = failure if failure
        Rails.logger.info("[Ai::Replay] #{payload.to_json}")
      end
    end
  end
end
