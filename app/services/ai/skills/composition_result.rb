# frozen_string_literal: true

module Ai
  module Skills
    # Structured result of skill composition. Safe for audit, debug, replay.
    class CompositionResult
      attr_reader :reply_text, :filled_slots, :contributing_skills, :suppressed_skills,
                  :conflict_resolutions, :precedence_rules_applied, :composition_mode

      def initialize(
        reply_text:,
        filled_slots: {},
        contributing_skills: [],
        suppressed_skills: [],
        conflict_resolutions: [],
        precedence_rules_applied: [],
        composition_mode: nil
      )
        @reply_text = reply_text.to_s
        @filled_slots = filled_slots.is_a?(Hash) ? filled_slots.deep_stringify_keys : {}
        @contributing_skills = contributing_skills.to_a.map(&:to_s)
        @suppressed_skills = suppressed_skills.to_a.map(&:to_s)
        @conflict_resolutions = conflict_resolutions.to_a
        @precedence_rules_applied = precedence_rules_applied.to_a
        @composition_mode = composition_mode.to_s.presence
      end

      def to_audit_hash
        {
          filled_response_slots: @filled_slots.keys,
          contributing_skills: @contributing_skills,
          suppressed_skills: @suppressed_skills.presence,
          conflict_resolutions: @conflict_resolutions.presence,
          precedence_rules_applied: @precedence_rules_applied.presence,
          final_skill_composition_mode: @composition_mode.presence
        }.compact
      end
    end
  end
end
