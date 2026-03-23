# frozen_string_literal: true

module Ai
  module Skills
    # Rule-based conflict resolution for multiple skill outputs.
    # All precedence is explicit and testable — not heuristic "best effort."
    #
    # Rules (see PRECEDENCE_RULES):
    # - Deterministic explanation skills beat non-deterministic / generic phrasing for primary_explanation.
    # - Among multiple deterministic primaries, CANONICAL_PRIMARY_ORDER picks one canonical path.
    # - followup_rewriter (style_transform) may restyle final text; it does not replace factual primary.
    # - discrepancy_detector and similar use supporting_analysis only — never overrides totals/state.
    # - docs_clarification is additive; never replaces deterministic primary (docs_supports_not_replaces_primary).
    class ConflictResolver
      PRECEDENCE_RULES = [
        'deterministic_skill_over_generic',
        'canonical_primary_precedence',
        'no_duplicate_primary_slot',
        'duplicate_explanation_text_suppressed',
        'additive_slots_append_only',
        'docs_clarification_supports_not_replaces_primary',
        'followup_rewriter_style_only',
        'discrepancy_adds_analysis_not_totals'
      ].freeze

      # Stable reason codes for audit/debug when a skill is suppressed.
      module ReasonCodes
        DETERMINISTIC_OVER_GENERIC = 'deterministic_over_generic'
        CANONICAL_PRIMARY = 'canonical_primary_precedence'
        DUPLICATE_PRIMARY = 'no_duplicate_primary_slot'
        DUPLICATE_TEXT = 'duplicate_explanation_text'
      end

      class << self
        # @param candidates [Array<Hash>] each: { skill_key:, slot:, text:, deterministic: }
        # @param tool_reply [String] original tool/renderer output
        # @return [Hash] primary_text, filled_slots, contributing, suppressed, suppressed_reasons, resolutions, rules_applied, deterministic_primary, style_transform_applied
        def resolve(candidates:, tool_reply:)
          return default_result(tool_reply) if candidates.blank?

          rules_applied = []
          filled = {}
          contributing = []
          suppressed = []
          suppressed_reasons = []
          resolutions = []

          primary_candidates = candidates.select { |c| c[:slot] == :primary_explanation && c[:text].present? }
          deterministic_primary = false
          style_transform_applied = false

          if primary_candidates.size > 1
            deterministic_ones = primary_candidates.select { |c| c[:deterministic] }
            non_det = primary_candidates.reject { |c| c[:deterministic] }

            if deterministic_ones.size >= 1 && non_det.any?
              winner = pick_canonical_deterministic(deterministic_ones) || deterministic_ones.first
              filled[:primary_explanation] = primary_entry(winner)
              contributing << winner[:skill_key]
              deterministic_primary = true
              non_det.each do |c|
                suppress(c[:skill_key], ReasonCodes::DETERMINISTIC_OVER_GENERIC, suppressed, suppressed_reasons, resolutions)
              end
              deterministic_ones.reject { |w| w[:skill_key] == winner[:skill_key] }.each do |c|
                suppress(c[:skill_key], ReasonCodes::CANONICAL_PRIMARY, suppressed, suppressed_reasons, resolutions)
              end
              rules_applied << 'deterministic_skill_over_generic'
              rules_applied << 'canonical_primary_precedence' if deterministic_ones.size > 1
            elsif deterministic_ones.size > 1
              winner = pick_canonical_deterministic(deterministic_ones)
              filled[:primary_explanation] = primary_entry(winner)
              contributing << winner[:skill_key]
              deterministic_primary = true
              deterministic_ones.reject { |w| w[:skill_key] == winner[:skill_key] }.each do |c|
                suppress(c[:skill_key], ReasonCodes::CANONICAL_PRIMARY, suppressed, suppressed_reasons, resolutions)
              end
              rules_applied << 'canonical_primary_precedence'
            elsif non_det.size > 1
              winner = primary_candidates.first
              filled[:primary_explanation] = primary_entry(winner)
              contributing << winner[:skill_key]
              primary_candidates[1..].each do |c|
                suppress(c[:skill_key], ReasonCodes::DUPLICATE_PRIMARY, suppressed, suppressed_reasons, resolutions)
              end
              rules_applied << 'no_duplicate_primary_slot'
            else
              winner = primary_candidates.first
              filled[:primary_explanation] = primary_entry(winner)
              contributing << winner[:skill_key]
              deterministic_primary = !!winner[:deterministic]
            end
          elsif primary_candidates.any?
            winner = primary_candidates.first
            filled[:primary_explanation] = primary_entry(winner)
            contributing << winner[:skill_key]
            deterministic_primary = !!winner[:deterministic]
          elsif tool_reply.present?
            filled[:primary_explanation] = { skill_key: 'tool_renderer', text: tool_reply, deterministic: true }
            deterministic_primary = true
          end

          additive = candidates.select { |c| ResponseSlots.additive?(c[:slot]) && c[:text].present? }
          additive.each do |c|
            slot_sym = c[:slot].to_sym
            next if slot_sym == :docs_clarification && deterministic_primary && redundant_docs_clarification?(filled, c[:text])

            filled[slot_sym] ||= []
            filled[slot_sym] = Array(filled[slot_sym]) unless filled[slot_sym].is_a?(Array)
            filled[slot_sym] << { skill_key: c[:skill_key], text: c[:text] }
            contributing << c[:skill_key] unless contributing.include?(c[:skill_key])
          end
          rules_applied << 'additive_slots_append_only' if additive.any?
          rules_applied << 'docs_clarification_supports_not_replaces_primary' if additive.any? { |x| x[:slot] == :docs_clarification }

          style_candidates = candidates.select { |c| c[:slot] == :style_transform && c[:text].present? }
          if style_candidates.any?
            winner = style_candidates.first
            filled[:style_transform] = { skill_key: winner[:skill_key], text: winner[:text], deterministic: false }
            contributing << winner[:skill_key] unless contributing.include?(winner[:skill_key])
            style_transform_applied = true
            rules_applied << 'followup_rewriter_style_only'
          end

          primary_text = build_reply(filled, tool_reply)
          {
            primary_text: primary_text,
            filled_slots: filled,
            contributing: contributing.map(&:to_sym).uniq,
            suppressed: suppressed.map(&:to_sym).uniq,
            suppressed_reasons: suppressed_reasons,
            resolutions: resolutions,
            rules_applied: rules_applied.uniq,
            deterministic_primary: deterministic_primary,
            style_transform_applied: style_transform_applied
          }
        end

        private

        def primary_entry(candidate)
          {
            skill_key: candidate[:skill_key],
            text: candidate[:text],
            deterministic: !!candidate[:deterministic]
          }
        end

        def pick_canonical_deterministic(list)
          list.min_by { |c| ResponseSlots.canonical_primary_rank(c[:skill_key]) }
        end

        def suppress(skill_key, reason_code, suppressed, suppressed_reasons, resolutions)
          sk = skill_key.to_sym
          suppressed << sk unless suppressed.include?(sk)
          suppressed_reasons << { 'skill_key' => sk.to_s, 'reason_code' => reason_code }
          resolutions << { rule: reason_code, suppressed_skill: sk.to_s }
        end

        def redundant_docs_clarification?(filled, text)
          primary = filled[:primary_explanation]
          return false unless primary.is_a?(Hash)

          normalize(primary[:text]) == normalize(text)
        end

        def normalize(s)
          s.to_s.strip.downcase.gsub(/\s+/, ' ')
        end

        def default_result(tool_reply)
          det = tool_reply.present?
          filled = det ? { primary_explanation: { skill_key: 'tool_renderer', text: tool_reply, deterministic: true } } : {}
          {
            primary_text: tool_reply.to_s,
            filled_slots: filled,
            contributing: [],
            suppressed: [],
            suppressed_reasons: [],
            resolutions: [],
            rules_applied: [],
            deterministic_primary: det,
            style_transform_applied: false
          }
        end

        def build_reply(filled, tool_reply)
          primary = filled[:primary_explanation]
          primary_text = primary.is_a?(Hash) ? primary[:text] : Array(primary).first&.dig(:text)
          primary_text ||= tool_reply.to_s

          style = filled[:style_transform]
          style_text = style.is_a?(Hash) ? style[:text] : nil
          final = style_text.presence || primary_text

          parts = [final]
          %i[supporting_analysis warnings next_steps docs_clarification].each do |slot|
            arr = filled[slot]
            next unless arr.is_a?(Array) && arr.any?

            arr.each do |entry|
              text = entry.is_a?(Hash) ? entry[:text] : entry.to_s
              parts << text if text.present?
            end
          end
          parts.reject(&:blank?).join("\n\n")
        end
      end
    end
  end
end
