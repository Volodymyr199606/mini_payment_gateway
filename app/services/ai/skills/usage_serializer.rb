# frozen_string_literal: true

module Ai
  module Skills
    # Normalizes skill usage metadata to a stable, safe shape for audit, debug, replay, analytics.
    # Strips unsafe fields; keeps only bounded metadata.
    class UsageSerializer
      SAFE_KEYS = %w[
        skill_key agent_key phase invoked success deterministic
        reason_code affected_final_response duration_ms
      ].freeze

      class << self
        # @param raw [Hash, InvocationResult, Array] raw invocation result(s)
        # @param agent_key [String] agent that invoked
        # @param affected_final_response [Boolean] whether skill output changed the reply
        # @return [Array<Hash>] array of safe, normalized skill usage hashes
        def normalize(raw:, agent_key: nil, affected_final_response: false)
          items = Array(raw)
          items.map do |item|
            normalize_one(item, agent_key: agent_key, affected_final_response: affected_final_response)
          end.compact
        end

        # @param raw [Hash, InvocationResult]
        # @return [Hash, nil] single safe hash or nil
        def normalize_one(raw, agent_key: nil, affected_final_response: false)
          return nil if raw.blank?

          h = raw.is_a?(InvocationResult) ? raw.to_audit_hash : raw.to_h.deep_stringify_keys
          out = {
            'skill_key' => (h['skill_key'] || h[:skill_key]).to_s.presence,
            'agent_key' => (agent_key || h['agent_key'] || h[:agent_key]).to_s.presence,
            'phase' => (h['phase'] || h[:phase]).to_s.presence,
            'invoked' => !!h['invoked'] || !!h[:invoked],
            'success' => h.key?('success') ? !!h['success'] : (h.key?(:success) ? !!h[:success] : nil),
            'deterministic' => h.key?('deterministic') ? !!h['deterministic'] : (h.key?(:deterministic) ? !!h[:deterministic] : nil),
            'reason_code' => (h['reason_code'] || h[:reason_code]).to_s.strip.presence,
            'affected_final_response' => h.key?('affected_final_response') ? !!h['affected_final_response'] : !!affected_final_response,
            'duration_ms' => ((n = (h['duration_ms'] || h[:duration_ms]).to_i).positive? ? n : nil)
          }.compact
          out['skill_key'].present? ? out : nil
        end

        # @param normalized [Array<Hash>]
        # @return [Hash] compact summary for analytics
        def summary(normalized)
          list = Array(normalized)
          return { skill_count: 0, skill_keys: [], skill_phases: [], skill_failures: 0, affected_response_count: 0 } if list.empty?

          invoked = list.select { |s| s['invoked'] || s[:invoked] }
          failed = invoked.reject { |s| s['success'] || s[:success] }
          affected = list.select { |s| s['affected_final_response'] || s[:affected_final_response] }

          {
            skill_count: invoked.size,
            skill_keys: invoked.map { |s| s['skill_key'] || s[:skill_key] }.compact.uniq,
            skill_phases: invoked.map { |s| s['phase'] || s[:phase] }.compact.uniq,
            skill_failures: failed.size,
            affected_response_count: affected.size
          }
        end
      end
    end
  end
end
