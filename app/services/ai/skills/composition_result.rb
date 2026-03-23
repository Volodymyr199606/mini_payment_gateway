# frozen_string_literal: true

module Ai
  module Skills
    # Structured result of skill composition. Safe for audit, debug, replay.
    class CompositionResult
      attr_reader :reply_text, :filled_slots, :contributing_skills, :suppressed_skills,
                  :suppressed_reason_codes, :conflict_resolutions, :precedence_rules_applied,
                  :composition_mode, :style_transform_applied, :deterministic_primary

      def initialize(
        reply_text:,
        filled_slots: {},
        contributing_skills: [],
        suppressed_skills: [],
        suppressed_reason_codes: [],
        conflict_resolutions: [],
        precedence_rules_applied: [],
        composition_mode: nil,
        style_transform_applied: false,
        deterministic_primary: false
      )
        @reply_text = reply_text.to_s
        @filled_slots = filled_slots.is_a?(Hash) ? filled_slots.deep_stringify_keys : {}
        @contributing_skills = contributing_skills.to_a.map(&:to_s)
        @suppressed_skills = suppressed_skills.to_a.map(&:to_s)
        @suppressed_reason_codes = Array(suppressed_reason_codes)
        @conflict_resolutions = conflict_resolutions.to_a
        @precedence_rules_applied = precedence_rules_applied.to_a
        @composition_mode = composition_mode.to_s.presence
        @style_transform_applied = !!style_transform_applied
        @deterministic_primary = !!deterministic_primary
      end

      def to_audit_hash
        {
          filled_response_slots: @filled_slots.keys,
          contributing_skills: @contributing_skills,
          suppressed_skills: @suppressed_skills.presence,
          suppressed_reason_codes: @suppressed_reason_codes.presence,
          conflict_resolutions: @conflict_resolutions.presence,
          precedence_rules_applied: @precedence_rules_applied.presence,
          final_skill_composition_mode: @composition_mode.presence,
          style_transform_applied: @style_transform_applied,
          deterministic_primary: @deterministic_primary
        }.compact
      end
    end
  end
end
