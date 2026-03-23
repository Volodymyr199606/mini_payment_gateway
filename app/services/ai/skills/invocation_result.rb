# frozen_string_literal: true

module Ai
  module Skills
    # Structured result of a skill invocation attempt. Safe for audit, debug, replay.
    class InvocationResult
      attr_reader :skill_key, :phase, :invoked, :reason_code,
                  :success, :deterministic, :skill_result, :metadata

      def initialize(
        skill_key:,
        phase:,
        invoked:,
        reason_code: nil,
        success: nil,
        deterministic: nil,
        skill_result: nil,
        metadata: {}
      )
        @skill_key = skill_key.to_sym
        @phase = phase.to_s
        @invoked = !!invoked
        @reason_code = reason_code.to_s.strip.presence
        @success = invoked ? !!skill_result&.success : nil
        @deterministic = invoked && skill_result ? !!skill_result.deterministic : nil
        @skill_result = skill_result
        @metadata = metadata.is_a?(Hash) ? metadata.deep_stringify_keys : {}
      end

      def self.skipped(skill_key:, phase:, reason_code:)
        new(
          skill_key: skill_key,
          phase: phase,
          invoked: false,
          reason_code: reason_code
        )
      end

      def self.executed(skill_key:, phase:, reason_code:, skill_result:)
        new(
          skill_key: skill_key,
          phase: phase,
          invoked: true,
          reason_code: reason_code,
          success: skill_result.success,
          deterministic: skill_result.deterministic,
          skill_result: skill_result
        )
      end

      def explanation
        @skill_result&.explanation
      end

      def data
        @skill_result&.data
      end

      def to_audit_hash
        h = {
          skill_key: @skill_key.to_s,
          phase: @phase,
          invoked: @invoked,
          reason_code: @reason_code,
          success: @success,
          deterministic: @deterministic
        }.merge(@metadata).compact
        if @invoked && @skill_result.respond_to?(:explanation)
          ex = @skill_result.explanation
          h[:explanation] = ex if ex.present?
        end
        h
      end
    end
  end
end
