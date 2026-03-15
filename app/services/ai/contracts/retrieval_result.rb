# frozen_string_literal: true

module Ai
  module Contracts
    # Contract for RAG retrieval result (RetrievalService / ContextBudgeter output).
    # Stable keys: context_text, citations, context_truncated, final_context_chars, final_sections_count.
    class RetrievalResult
      attr_reader :context_text, :citations, :context_truncated,
                  :final_context_chars, :final_sections_count, :dropped_section_ids_count,
                  :debug, :contract_version

      def initialize(
        context_text: nil,
        citations: [],
        context_truncated: false,
        final_context_chars: nil,
        final_sections_count: nil,
        dropped_section_ids_count: nil,
        debug: nil,
        contract_version: nil
      )
        @context_text = context_text.to_s.presence
        @citations = citations.is_a?(Array) ? citations : []
        @context_truncated = !!context_truncated
        @final_context_chars = final_context_chars.is_a?(Integer) ? final_context_chars : nil
        @final_sections_count = final_sections_count.is_a?(Integer) ? final_sections_count : nil
        @dropped_section_ids_count = dropped_section_ids_count.is_a?(Integer) ? dropped_section_ids_count : nil
        @debug = debug.is_a?(Hash) ? debug : nil
        @contract_version = contract_version || Contracts::RETRIEVAL_RESULT_VERSION
      end

      def self.from_h(h)
        return nil if h.blank? || !h.is_a?(Hash)

        sym = h.with_indifferent_access
        new(
          context_text: sym[:context_text],
          citations: sym[:citations].to_a,
          context_truncated: !!sym[:context_truncated],
          final_context_chars: sym[:final_context_chars],
          final_sections_count: sym[:final_sections_count],
          dropped_section_ids_count: sym[:dropped_section_ids_count],
          debug: sym[:debug],
          contract_version: sym[:contract_version].presence
        )
      end

      def to_h
        out = {
          context_text: @context_text,
          citations: @citations,
          context_truncated: @context_truncated,
          final_context_chars: @final_context_chars,
          final_sections_count: @final_sections_count,
          contract_version: @contract_version
        }
        out[:dropped_section_ids_count] = @dropped_section_ids_count if @dropped_section_ids_count.present?
        out[:debug] = @debug if @debug.present?
        out
      end
    end
  end
end
