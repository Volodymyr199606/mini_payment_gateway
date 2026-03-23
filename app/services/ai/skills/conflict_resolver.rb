# frozen_string_literal: true

module Ai
  module Skills
    # Rule-based conflict resolution for multiple skill outputs.
    # Precedence: deterministic beats generic LLM; no duplicate slots; additive only for supporting.
    class ConflictResolver
      PRECEDENCE_RULES = [
        'deterministic_skill_over_generic',
        'followup_rewriter_style_only',
        'discrepancy_adds_analysis_not_totals',
        'docs_clarification_supports_not_replaces',
        'no_duplicate_explanation_slot',
        'additive_slots_append_only'
      ].freeze

      class << self
        # @param candidates [Array<Hash>] each: { skill_key:, slot:, text:, deterministic: }
        # @param tool_reply [String] original tool/renderer output
        # @return [Hash] { primary_text:, filled_slots:, contributing:, suppressed:, resolutions:, rules_applied: }
        def resolve(candidates:, tool_reply:)
          return default_result(tool_reply) if candidates.blank?

          rules_applied = []
          filled = {}
          contributing = []
          suppressed = []
          resolutions = []

          # Rule: deterministic skill output beats generic tool phrasing when both target primary_explanation
          primary_candidates = candidates.select { |c| c[:slot] == :primary_explanation && c[:text].present? }
          if primary_candidates.size > 1
            deterministic = primary_candidates.find { |c| c[:deterministic] }
            generic = primary_candidates.find { |c| !c[:deterministic] }
            if deterministic && generic
              filled[:primary_explanation] = { skill_key: deterministic[:skill_key], text: deterministic[:text] }
              contributing << deterministic[:skill_key]
              suppressed << generic[:skill_key]
              resolutions << { rule: 'deterministic_over_generic', winner: deterministic[:skill_key], loser: generic[:skill_key] }
              rules_applied << 'deterministic_skill_over_generic'
            else
              winner = primary_candidates.first
              filled[:primary_explanation] = { skill_key: winner[:skill_key], text: winner[:text] }
              contributing << winner[:skill_key]
              primary_candidates[1..].each { |c| suppressed << c[:skill_key] }
              rules_applied << 'no_duplicate_explanation_slot'
            end
          elsif primary_candidates.any?
            winner = primary_candidates.first
            filled[:primary_explanation] = { skill_key: winner[:skill_key], text: winner[:text] }
            contributing << winner[:skill_key]
          elsif tool_reply.present?
            filled[:primary_explanation] = { skill_key: 'tool_renderer', text: tool_reply }
          end

          # Additive slots: supporting_analysis, warnings, next_steps
          additive = candidates.select { |c| ResponseSlots.additive?(c[:slot]) && c[:text].present? }
          additive.each do |c|
            slot_key = c[:slot].to_s
            filled[slot_key] ||= []
            filled[slot_key] = Array(filled[slot_key]) unless filled[slot_key].is_a?(Array)
            filled[slot_key] << { skill_key: c[:skill_key], text: c[:text] }
            contributing << c[:skill_key] unless contributing.include?(c[:skill_key])
          end
          rules_applied << 'additive_slots_append_only' if additive.any?

          # Style slot: followup_rewriter only; does not override factual content
          style_candidates = candidates.select { |c| c[:slot] == :style_transform && c[:text].present? }
          if style_candidates.any?
            winner = style_candidates.first
            filled[:style_transform] = { skill_key: winner[:skill_key], text: winner[:text] }
            contributing << winner[:skill_key] unless contributing.include?(winner[:skill_key])
            rules_applied << 'followup_rewriter_style_only'
          end

          reply_text = build_reply(filled, tool_reply)
          {
            primary_text: reply_text,
            filled_slots: filled,
            contributing: contributing.uniq,
            suppressed: suppressed.uniq,
            resolutions: resolutions,
            rules_applied: rules_applied.uniq
          }
        end

        private

        def default_result(tool_reply)
          filled = tool_reply.present? ? { primary_explanation: { skill_key: 'tool_renderer', text: tool_reply } } : {}
          {
            primary_text: tool_reply.to_s,
            filled_slots: filled,
            contributing: [],
            suppressed: [],
            resolutions: [],
            rules_applied: []
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
          %i[supporting_analysis warnings next_steps].each do |slot|
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
