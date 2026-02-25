# frozen_string_literal: true

module Ai
  module Rag
    # Retrieves top 2–3 doc sections for a message, deduped by file.
    # Returns { context_text:, citations: [{ file:, heading:, anchor:, excerpt: }] }
    class DocsRetriever
      MAX_SECTIONS = 3
      MAX_CHARS_PER_SECTION = 1200
      EXCERPT_LENGTH = 160

      def initialize(message)
        @message = message.to_s
      end

      def call
        index = DocsIndex.instance
        top_sections = index.search(@message, top_k: 5)
        deduped = dedupe_by_file(top_sections, MAX_SECTIONS)
        context_parts = []
        citations = []

        deduped.each do |s|
          content = s[:content].to_s.truncate(MAX_CHARS_PER_SECTION)
          context_parts << "---\n[#{s[:file]} :: #{s[:heading]}]\n#{content}"
          citations << build_citation(s)
        end

        context_text = context_parts.join("\n\n").presence || nil
        { context_text: context_text, citations: citations }
      end

      private

      def build_citation(section)
        content = section[:content].to_s
        {
          file: section[:file],
          heading: section[:heading],
          anchor: slugify(section[:heading].to_s),
          excerpt: content.truncate(EXCERPT_LENGTH)
        }
      end

      def slugify(text)
        text.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-|-\z/, '')
      end

      def dedupe_by_file(sections, max)
        seen = {}
        sections.each_with_object([]) do |s, acc|
          next if acc.size >= max
          key = s[:file]
          next if seen[key]
          seen[key] = true
          acc << s
        end
      end
    end
  end
end
