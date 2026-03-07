# frozen_string_literal: true

module Ai
  module Rag
    # Merges keyword (DocsIndex) and vector (DocSectionEmbedding) retrieval, then reranks with RRF.
    # Returns { sections:, seed_ids: } for RetrievalService. Used when AI_VECTOR_RAG_ENABLED=true.
    class HybridRetriever
      KEYWORD_TOP_K = 4
      VECTOR_TOP_K = 4
      FINAL_TOP_K = 6
      RRF_K = 60
      # Slight boost for keyword hits so keyword-only sections can outrank vector-only when ranks are close.
      KEYWORD_RRF_BOOST = 1.2
      MAX_CHARS_PER_SECTION = 1000

      def initialize(message, agent_key: nil, keyword_retriever: nil, embedding_client: nil, graph: nil, vector_store: nil)
        @message = message.to_s
        @agent_key = agent_key
        @keyword_retriever = keyword_retriever || DocsIndex.instance
        @embedding_client = embedding_client || EmbeddingClient.new
        @graph = graph || ContextGraph.instance
        @vector_store = vector_store
      end

      # Returns { sections:, seed_ids: }. sections = [{ content_chunk:, citation:, id: }] in reranked order.
      def call
        keyword_hits = fetch_keyword_hits
        keyword_section_ids = keyword_hits.map { |s| section_id_from_hit(s) }

        vector_pairs = fetch_vector_hits
        vector_section_ids = vector_pairs.map(&:first)

        merged_ids = merge_and_dedup(keyword_section_ids, vector_section_ids)
        reranked = rerank_rrf(
          keyword_section_ids: keyword_section_ids,
          vector_section_ids: vector_section_ids
        )
        top_ids = reranked.first(FINAL_TOP_K).map(&:first)
        seed_ids = keyword_section_ids.first(3)

        sections = build_sections(top_ids)
        { sections: sections, seed_ids: seed_ids, vector_hits_count: vector_section_ids.size }
      end

      private

      def fetch_keyword_hits
        policy = AgentDocPolicy.for_agent(@agent_key) if @agent_key
        opts = { top_k: KEYWORD_TOP_K }
        opts[:allowed_files] = policy[:allowed] if policy&.dig(:allowed).present?
        preferred = (policy&.dig(:preferred).presence || []).dup
        preferred.concat(DocsRetriever::CORE_DOCS)
        opts[:preferred_files] = preferred.uniq
        @keyword_retriever.search(@message, **opts)
      end

      def section_id_from_hit(hit)
        Helpers.section_id(Helpers.normalize_file(hit[:file]), Helpers.slugify_heading(hit[:heading].to_s))
      end

      def fetch_vector_hits
        query_embedding = @embedding_client.embed(@message)
        return [] unless query_embedding.is_a?(Array) && query_embedding.size == EmbeddingClient::DIMENSIONS

        if @vector_store
          @vector_store.nearest(query_embedding, limit: VECTOR_TOP_K)
        elsif defined?(DocSectionEmbedding)
          DocSectionEmbedding.nearest(query_embedding, limit: VECTOR_TOP_K)
        else
          []
        end
      end

      def merge_and_dedup(keyword_ids, vector_ids)
        (keyword_ids + vector_ids).uniq
      end

      # RRF: score(id) = sum weight/(k + rank) over each list. Keyword list uses KEYWORD_RRF_BOOST.
      # Returns [[section_id, score], ...] sorted by score desc.
      def rerank_rrf(keyword_section_ids:, vector_section_ids:)
        k = RRF_K
        scores = Hash.new(0.0)

        keyword_section_ids.each_with_index do |sid, idx|
          scores[sid] += KEYWORD_RRF_BOOST / (k + idx + 1)
        end
        vector_section_ids.each_with_index do |sid, idx|
          scores[sid] += 1.0 / (k + idx + 1)
        end

        scores.sort_by { |_, score| -score }
      end

      def build_sections(ids)
        ids.filter_map do |sid|
          node = @graph.node(sid)
          next unless node

          content = node[:content].to_s.truncate(MAX_CHARS_PER_SECTION)
          header = "## #{node[:heading]} (#{node[:file]}##{node[:anchor]})"
          {
            content_chunk: "#{header}\n#{content}",
            citation: Helpers.build_citation(node),
            id: node[:id]
          }
        end
      end
    end
  end
end
