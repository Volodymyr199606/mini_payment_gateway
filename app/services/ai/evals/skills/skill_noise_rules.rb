# frozen_string_literal: true

module Ai
  module Evals
    module Skills
      # Explicit, testable noise rules for the skill layer (no LLM text checks).
      module SkillNoiseRules
        class << self
          # Multiple skills filling primary_explanation with deterministic text for same fact
          # (heuristic: more than one deterministic primary candidate for same slot)
          def duplicate_deterministic_primary?(composition_result)
            return false unless composition_result.respond_to?(:filled_slots)

            filled = composition_result.filled_slots
            return false unless filled.is_a?(Hash)

            prim = filled[:primary_explanation] || filled['primary_explanation']
            return false if prim.blank?

            # Array form = multiple contributions to same slot
            prim.is_a?(Array) && prim.size > 1 && prim.all? { |p| p.is_a?(Hash) && (p[:deterministic] || p['deterministic']) }
          end

          # Heavy analysis on a trivial support lookup (explicit disallowed skill keys)
          def heavy_on_trivial_support?(invoked_skill_keys, trivial: true)
            return false unless trivial

            keys = Array(invoked_skill_keys).map(&:to_sym)
            heavy = %i[discrepancy_detector reporting_trend_summary]
            (keys & heavy).any?
          end

          # @param invoked_keys [Array<Symbol>] successful invocations
          # @param style_only [Boolean] whether request is in concise_rewrite / style path
          def followup_rewriter_without_style_path?(invoked_keys, style_only:)
            return false if style_only

            Array(invoked_keys).map(&:to_sym).include?(:followup_rewriter)
          end

          # Too many distinct slots filled for a simple single-skill request
          def too_many_slots_filled?(filled_slots_count, max_slots: 3)
            filled_slots_count.to_i > max_slots
          end
        end
      end
    end
  end
end
