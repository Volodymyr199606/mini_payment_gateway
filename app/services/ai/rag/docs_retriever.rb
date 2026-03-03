# frozen_string_literal: true

module Ai
  module Rag
    # Retrieves doc sections via keyword search, then expands with ContextGraph to include
    # related parent/neighbor/linked sections. Returns a bundle of up to 6 sections.
    # Optional agent_key: restricts and boosts by AgentDocPolicy (allowed + preferred files).
    # Returns { context_text:, citations: [{ file:, heading:, anchor:, excerpt: }] }
    class DocsRetriever
      MAX_SECTIONS = 6
      MAX_CHARS_PER_SECTION = 1000
      MAX_CONTEXT_CHARS = 5000
      EXCERPT_LENGTH = 160
      SEED_SECTIONS = 3
      CORE_DOCS = %w[
        docs/PAYMENT_LIFECYCLE.md
        docs/ARCHITECTURE.md
        docs/REFUNDS_API.md
        docs/SECURITY.md
      ].freeze

      def initialize(message, agent_key: nil)
        @message = message.to_s
        @agent_key = agent_key
      end

      def call
        index = DocsIndex.instance
        policy = AgentDocPolicy.for_agent(@agent_key) if @agent_key
        search_opts = { top_k: 6 }
        search_opts[:allowed_files] = policy[:allowed] if policy && policy[:allowed].present?
        preferred = (policy && policy[:preferred].present? ? policy[:preferred] : []).dup
        preferred.concat(CORE_DOCS)
        search_opts[:preferred_files] = preferred.uniq

        initial_hits = index.search(@message, **search_opts)
        seed_ids = section_ids_from_deduped(initial_hits, SEED_SECTIONS)

        graph = ContextGraph.instance
        expanded_ids = seed_ids.empty? ? [] : graph.expand(seed_ids, max_hops: 1, max_nodes: MAX_SECTIONS)

        context_parts = []
        citations = []
        total_chars = 0

        expanded_ids.each do |sid|
          break if total_chars >= MAX_CONTEXT_CHARS
          node = graph.node(sid)
          next unless node

          content = node[:content].to_s.truncate(MAX_CHARS_PER_SECTION)
          header = "## #{node[:heading]} (#{node[:file]}##{node[:anchor]})"
          chunk = "#{header}\n#{content}"
          remaining = MAX_CONTEXT_CHARS - total_chars
          if chunk.length > remaining
            content = content.truncate([MAX_CHARS_PER_SECTION, remaining - header.length - 2].min)
            chunk = "#{header}\n#{content}"
          end
          total_chars += chunk.length
          context_parts << chunk
          citations << build_citation_from_node(node)
        end

        # Fallback: if graph yielded nothing (e.g. no docs), use initial index sections
        if context_parts.empty? && initial_hits.any?
          deduped = dedupe_by_file(initial_hits, MAX_SECTIONS)
          deduped.each do |s|
            content = s[:content].to_s.truncate(MAX_CHARS_PER_SECTION)
            header = "## #{s[:heading]} (#{s[:file].to_s.gsub('\\', '/')}##{slugify(s[:heading].to_s)})"
            context_parts << "#{header}\n#{content}"
            citations << build_citation(s)
          end
        end

        context_text = context_parts.join("\n\n").presence || nil
        { context_text: context_text, citations: citations }
      end

      private

      def section_ids_from_deduped(sections, max)
        deduped = dedupe_by_file(sections, max)
        deduped.map do |s|
          file = s[:file].to_s.gsub('\\', '/')
          section_id(file, slugify(s[:heading].to_s))
        end
      end

      def section_id(file, anchor)
        "#{file}##{anchor}"
      end

      def build_citation_from_node(node)
        content = node[:content].to_s
        {
          file: node[:file],
          heading: node[:heading],
          anchor: node[:anchor],
          excerpt: content.truncate(EXCERPT_LENGTH)
        }
      end

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
        text.to_s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-|-\z/, '')
      end

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
