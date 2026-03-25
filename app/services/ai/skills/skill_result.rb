# frozen_string_literal: true

module Ai
  module Skills
    # Structured output from a skill execution. Stable shape for composition, audit, replay, and analytics.
    # Bump only with `Ai::Skills::PlatformV1::CONTRACT_SCHEMA_VERSION` and a migration note.
    class SkillResult
      CONTRACT_SCHEMA_VERSION = '1.0.0'

      attr_reader :skill_key, :success, :data, :explanation, :metadata,
                  :safe_for_composition, :deterministic, :error_code, :error_message

      def initialize(
        skill_key:,
        success:,
        data: {},
        explanation: nil,
        metadata: {},
        safe_for_composition: true,
        deterministic: true,
        error_code: nil,
        error_message: nil
      )
        @skill_key = skill_key.to_sym
        @success = !!success
        @data = data.is_a?(Hash) ? data.deep_stringify_keys : {}
        @explanation = explanation&.to_s
        @metadata = metadata.is_a?(Hash) ? metadata.deep_stringify_keys : {}
        @safe_for_composition = !!safe_for_composition
        @deterministic = !!deterministic
        @error_code = error_code&.to_s
        @error_message = error_message&.to_s
      end

      def self.success(skill_key:, data: {}, explanation: nil, metadata: {}, safe_for_composition: true, deterministic: true)
        new(
          skill_key: skill_key,
          success: true,
          data: data,
          explanation: explanation,
          metadata: metadata,
          safe_for_composition: safe_for_composition,
          deterministic: deterministic
        )
      end

      def self.failure(skill_key:, error_code:, error_message:, metadata: {}, deterministic: true, safe_for_composition: true)
        new(
          skill_key: skill_key,
          success: false,
          data: {},
          metadata: metadata,
          safe_for_composition: safe_for_composition,
          deterministic: deterministic,
          error_code: error_code,
          error_message: error_message
        )
      end

      def failure?
        !@success
      end

      # Safe for audit/debug/replay (no raw secrets; stringifiable)
      def to_h
        {
          skill_key: @skill_key.to_s,
          success: @success,
          explanation: @explanation,
          metadata: @metadata,
          safe_for_composition: @safe_for_composition,
          deterministic: @deterministic,
          error_code: @error_code,
          error_message: @error_message
        }.tap do |h|
          h[:data] = @data if @success || @data.present?
        end.compact
      end
    end
  end
end
