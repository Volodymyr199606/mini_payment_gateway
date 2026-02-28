# frozen_string_literal: true

module Ai
  module Rag
    # Retrieves top 2–3 doc sections for a message, deduped by file.
    # Optional agent_key: restricts and boosts by AgentDocPolicy (allowed + preferred files).
    # Returns { context_text:, citations: [{ file:, heading:, anchor:, excerpt: }] }
    class DocsRetriever
      MAX_SECTIONS = 3
      MAX_CHARS_PER_SECTION = 1200
      EXCERPT_LENGTH = 160

      def initialize(message, agent_key: nil)
        @message = message.to_s
        @agent_key = agent_key
      end

      def call
        index = DocsIndex.instance
        policy = AgentDocPolicy.for_agent(@agent_key) if @agent_key
        search_opts = { top_k: 5 }
        search_opts[:allowed_files] = policy[:allowed] if policy && policy[:allowed].present?
        search_opts[:preferred_files] = policy[:preferred] if policy && policy[:preferred].present?

        top_sections = index.search(@message, **search_opts)
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

      # Allow up to 2 sections per file so we can return both "Authorize (in this project)"
      # and "Capture (in this project)" from PAYMENT_LIFECYCLE.md for authorize vs capture queries.
      def dedupe_by_file(sections, max)
        file_counts = Hash.new(0)
        sections.each_with_object([]) do |s, acc|
          next if acc.size >= max
          key = s[:file]
          next if file_counts[key] >= 2
          file_counts[key] += 1
          acc << s
        end
      end
    end
  end
end
