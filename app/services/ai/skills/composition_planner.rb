# frozen_string_literal: true

module Ai
  module Skills
    # Plans how multiple skill outputs combine into one response.
    # Applies precedence rules and produces a stable CompositionResult.
    class CompositionPlanner
      class << self
        # @param reply_text [String] base reply (from tool renderer or prior)
        # @param invocation_results [Array<Hash>] from InvocationCoordinator (to_audit_hash per skill)
        # @param agent_key [String, Symbol]
        # @return [CompositionResult]
        def plan(reply_text:, invocation_results: [], agent_key: nil)
          tool_reply = reply_text.to_s.strip.presence || ''

          invoked = Array(invocation_results).select { |r| r[:invoked] && r[:success] }
          return single_result(tool_reply, invoked, agent_key) if invoked.size <= 1

          candidates = invoked.map do |r|
            skill_key = (r[:skill_key] || r['skill_key']).to_sym
            slot = ResponseSlots.slot_for(skill_key)
            text = extract_explanation(r)
            next unless text.present?

            { skill_key: skill_key, slot: slot || :primary_explanation, text: text, deterministic: r[:deterministic] }
          end.compact

          resolved = ConflictResolver.resolve(candidates: candidates, tool_reply: tool_reply)
          build_result(resolved, agent_key)
        end

        private

        def extract_explanation(inv_result)
          h = inv_result.is_a?(Hash) ? inv_result.with_indifferent_access : {}
          h[:explanation].presence || h.dig(:skill_result, :explanation)
        end

        def single_result(tool_reply, invoked, agent_key)
          if invoked.any?
            r = invoked.first
            skill_key = (r[:skill_key] || r['skill_key']).to_s
            text = extract_explanation(r)
            slot = ResponseSlots.slot_for(skill_key.to_sym) || :primary_explanation
            reply = if ResponseSlots.additive?(slot) && tool_reply.present?
                      [tool_reply, text].compact.join("\n\n")
                    elsif ResponseSlots.style_only?(slot)
                      text.presence || tool_reply
                    else
                      text.presence || tool_reply
                    end
            filled = { slot.to_s => { skill_key: skill_key, text: text || tool_reply } }
            det = r[:deterministic] != false && r[:deterministic] != 'false'
            style_applied = ResponseSlots.style_only?(slot)
            CompositionResult.new(
              reply_text: reply,
              filled_slots: filled,
              contributing_skills: [skill_key],
              composition_mode: 'skill_primary',
              style_transform_applied: style_applied,
              deterministic_primary: det && !style_applied
            )
          else
            CompositionResult.new(
              reply_text: tool_reply,
              filled_slots: tool_reply.present? ? { 'primary_explanation' => { 'skill_key' => 'tool_renderer', 'text' => tool_reply, 'deterministic' => true } } : {},
              contributing_skills: [],
              composition_mode: 'tool_only',
              deterministic_primary: tool_reply.present?
            )
          end
        end

        def build_result(resolved, agent_key)
          filled = resolved[:filled_slots].transform_keys(&:to_s)
          CompositionResult.new(
            reply_text: resolved[:primary_text],
            filled_slots: filled,
            contributing_skills: resolved[:contributing],
            suppressed_skills: resolved[:suppressed],
            suppressed_reason_codes: resolved[:suppressed_reasons] || [],
            conflict_resolutions: resolved[:resolutions],
            precedence_rules_applied: resolved[:rules_applied],
            composition_mode: resolved[:contributing].any? ? 'skill_composed' : 'tool_only',
            style_transform_applied: resolved[:style_transform_applied] || false,
            deterministic_primary: resolved[:deterministic_primary] || false
          )
        end
      end
    end
  end
end
