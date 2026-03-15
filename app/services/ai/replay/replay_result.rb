# frozen_string_literal: true

module Ai
  module Replay
    # Structured result of a replay run: original vs replayed metadata and diff.
    class ReplayResult
      attr_reader :original_audit_id, :replay_possible, :replay_mode_used,
                  :original_summary, :replay_summary, :differences,
                  :matched_path, :matched_policy_decisions, :matched_tool_usage,
                  :matched_composition_mode, :matched_debug_metadata,
                  :notes, :reason_codes, :duration_ms, :replay_failure

      def initialize(
        original_audit_id: nil,
        replay_possible: false,
        replay_mode_used: true,
        original_summary: {},
        replay_summary: {},
        differences: [],
        matched_path: nil,
        matched_policy_decisions: nil,
        matched_tool_usage: nil,
        matched_composition_mode: nil,
        matched_debug_metadata: nil,
        notes: [],
        reason_codes: [],
        duration_ms: nil,
        replay_failure: nil
      )
        @original_audit_id = original_audit_id
        @replay_possible = replay_possible
        @replay_mode_used = !!replay_mode_used
        @original_summary = original_summary.to_h
        @replay_summary = replay_summary.to_h
        @differences = differences.to_a
        @matched_path = matched_path
        @matched_policy_decisions = matched_policy_decisions
        @matched_tool_usage = matched_tool_usage
        @matched_composition_mode = matched_composition_mode
        @matched_debug_metadata = matched_debug_metadata
        @notes = notes.to_a
        @reason_codes = reason_codes.to_a
        @duration_ms = duration_ms
        @replay_failure = replay_failure
      end

      def to_h
        {
          original_audit_id: @original_audit_id,
          replay_possible: @replay_possible,
          replay_mode_used: @replay_mode_used,
          original_summary: @original_summary,
          replay_summary: @replay_summary,
          differences: @differences,
          matched_path: @matched_path,
          matched_policy_decisions: @matched_policy_decisions,
          matched_tool_usage: @matched_tool_usage,
          matched_composition_mode: @matched_composition_mode,
          matched_debug_metadata: @matched_debug_metadata,
          notes: @notes,
          reason_codes: @reason_codes,
          duration_ms: @duration_ms,
          replay_failure: @replay_failure
        }.compact
      end
    end
  end
end
