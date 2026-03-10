# frozen_string_literal: true

module Ai
  module Rag
    # Deterministic context budgeting for retrieved sections.
    # Preserves ranked order; always includes top section; drops whole sections when over budget.
    # Does not partially truncate section bodies.
    class ContextBudgeter
      DEFAULT_MAX_CONTEXT_CHARS = 12_000
      DEFAULT_MAX_SECTIONS = 6
      DEFAULT_MAX_CITATIONS = 8

      class << self
        def max_context_chars
          (ENV['AI_MAX_CONTEXT_CHARS'].presence || DEFAULT_MAX_CONTEXT_CHARS).to_i
        end

        def max_sections
          (ENV['AI_MAX_RETRIEVED_SECTIONS'].presence || DEFAULT_MAX_SECTIONS).to_i
        end

        def max_citations
          (ENV['AI_MAX_CITATIONS'].presence || DEFAULT_MAX_CITATIONS).to_i
        end

        # sections: array of { id:, content_chunk:, citation: } in ranked order
        # Returns { context_text:, citations:, context_truncated:, included_section_ids:, dropped_section_ids_count:, final_context_chars:, final_sections_count: }
        def call(sections, max_context_chars: nil, max_sections: nil, max_citations: nil)
          max_context_chars ||= self.max_context_chars
          max_sections ||= self.max_sections
          max_citations ||= self.max_citations

          sections = sections.to_a
          if sections.empty?
            return {
              context_text: nil,
              citations: [],
              context_truncated: false,
              included_section_ids: [],
              dropped_section_ids_count: 0,
              final_context_chars: 0,
              final_sections_count: 0
            }
          end

          included = []
          total_chars = 0
          separator_len = 2 # "\n\n"

          sections.each do |sec|
            chunk = sec[:content_chunk].to_s
            len = chunk.length
            # Always include first (top-ranked) section even if over budget
            if included.empty?
              included << sec
              total_chars += len
              next
            end
            break if included.size >= max_sections
            break if included.size >= max_citations
            break if total_chars + separator_len + len > max_context_chars

            included << sec
            total_chars += separator_len + len
          end

          context_text = included.map { |s| s[:content_chunk].to_s }.join("\n\n").presence
          citations = included.map { |s| s[:citation] }
          included_ids = included.map { |s| s[:id] }.compact
          dropped_count = sections.size - included.size

          {
            context_text: context_text,
            citations: citations,
            context_truncated: dropped_count.positive?,
            included_section_ids: included_ids,
            dropped_section_ids_count: dropped_count,
            final_context_chars: context_text.to_s.length,
            final_sections_count: included.size
          }
        end
      end
    end
  end
end
