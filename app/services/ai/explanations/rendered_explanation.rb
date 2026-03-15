# frozen_string_literal: true

module Ai
  module Explanations
    # Result of rendering a deterministic explanation template.
    RenderedExplanation = Struct.new(
      :explanation_text,
      :explanation_type,
      :explanation_key,
      :deterministic,
      :metadata,
      keyword_init: true
    ) do
      def self.for_tool(explanation_text:, explanation_type:, explanation_key:, metadata: {})
        new(
          explanation_text: explanation_text,
          explanation_type: explanation_type,
          explanation_key: explanation_key,
          deterministic: true,
          metadata: metadata.to_h
        )
      end

      def to_audit_metadata
        {
          deterministic_explanation_used: true,
          explanation_type: explanation_type,
          explanation_key: explanation_key,
          llm_skipped_due_to_template: true
        }.merge(metadata.slice(:hybrid_explanation_used))
      end
    end
  end
end
