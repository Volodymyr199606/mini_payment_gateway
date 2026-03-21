# frozen_string_literal: true

module Ai
  module Skills
    # Handles simple follow-up rewrites (simpler, shorter, bullet points, etc.)
    # without full retrieval/tool orchestration. Reuses Resolver response_style
    # patterns. Bounded; semantic rewrites fall back to original with metadata.
    class FollowupRewriter < BaseSkill
      DEFINITION = SkillDefinition.new(
        key: :followup_rewriter,
        class_name: 'Ai::Skills::FollowupRewriter',
        description: 'Rewrite or clarify follow-up questions safely.',
        deterministic: false,
        dependencies: %i[memory context],
        input_contract: 'prior_assistant_content, response_style (simpler|shorter|bullet_points|only_important|more_technical)',
        output_contract: 'SkillResult with rewritten_text, rewrite_mode metadata'
      )

      def execute(context:)
        prior = context[:prior_assistant_content].to_s.strip
        return empty_prior_error(context) if prior.blank?

        styles = Array(context[:response_style] || context[:response_style_adjustments]).compact.map(&:to_sym)
        styles = extract_styles_from_message(context[:message]) if styles.empty? && context[:message].present?

        rewritten, mode = apply_rewrite(prior, styles)
        metadata = audit_metadata(context).merge('rewrite_mode' => mode.to_s)

        SkillResult.success(
          skill_key: :followup_rewriter,
          data: {
            rewritten_text: rewritten,
            rewrite_mode: mode.to_s,
            original_length: prior.length,
            rewritten_length: rewritten.length
          },
          explanation: rewritten,
          metadata: metadata,
          deterministic: false
        )
      rescue StandardError => e
        SkillResult.failure(
          skill_key: :followup_rewriter,
          error_code: 'execution_error',
          error_message: e.message,
          metadata: audit_metadata(context),
          deterministic: false
        )
      end

      private

      def extract_styles_from_message(msg)
        lower = msg.to_s.downcase
        styles = []
        styles << :simpler if lower.match?(/\b(simpler|simple|simply)\b/)
        styles << :shorter if lower.match?(/\b(shorter|brief|concise)\b/)
        styles << :more_detailed if lower.match?(/\b(more\s+detailed|detail|expand)\b/)
        styles << :more_technical if lower.match?(/\b(more\s+technical|technical)\b/)
        styles << :bullet_points if lower.match?(/\b(bullet|bullets|list)\b/)
        styles << :only_important if lower.match?(/\b(important\s+part|key\s+points|just\s+the\s+important)\b/)
        styles
      end

      def apply_rewrite(text, styles)
        return [text, :none] if styles.empty?

        result = text
        mode = :none

        if styles.include?(:bullet_points)
          result = to_bullet_points(result)
          mode = :bullet_points
        end
        if styles.include?(:shorter)
          result = truncate(result, 200)
          mode = mode == :bullet_points ? :bullet_points_shorter : :shorter
        end
        if styles.include?(:only_important) && mode == :none
          result = first_sentences(result, 2)
          mode = :only_important
        end
        if styles.include?(:simpler) && mode == :none
          mode = :semantic_rewrite_needed
        end
        if styles.include?(:more_technical) && mode == :none
          mode = :semantic_rewrite_needed
        end
        if styles.include?(:more_detailed) && mode == :none
          mode = :semantic_rewrite_needed
        end

        [result.presence || text, mode]
      end

      def to_bullet_points(text)
        paragraphs = text.split(/\n\n+/)
        lines = paragraphs.flat_map { |p| p.split(/(?<=[.!?])\s+/) }
        lines.reject(&:blank?).map { |l| "• #{l.strip}" }.join("\n")
      end

      def truncate(text, max_chars)
        return text if text.length <= max_chars
        cutoff = text[0, max_chars].rindex(/\s/) || max_chars
        text[0, cutoff].strip + '…'
      end

      def first_sentences(text, n)
        sentences = text.split(/(?<=[.!?])\s+/)
        sentences.first(n).join(' ').strip
      end

      def audit_metadata(context)
        {
          'agent_key' => context[:agent_key].to_s.presence,
          'merchant_id' => context[:merchant_id].to_s.presence
        }.compact
      end

      def empty_prior_error(context)
        SkillResult.failure(
          skill_key: :followup_rewriter,
          error_code: 'missing_prior',
          error_message: 'prior_assistant_content required for rewrite',
          metadata: audit_metadata(context),
          deterministic: false
        )
      end
    end
  end
end
