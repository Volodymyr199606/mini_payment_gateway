# frozen_string_literal: true

module Ai
  module Performance
    # Thin cache wrapper around RetrievalService. Does not modify RetrievalService.
    # When AI_DEBUG or AI_CACHE_BYPASS, cache is bypassed.
    class CachedRetrievalService
      def self.call(message, agent_key: nil, max_context_chars: nil, max_sections: nil, max_citations: nil)
        graph = ::Ai::Rag::RetrievalService.context_graph_enabled?
        vector = ::Ai::Rag::RetrievalService.vector_rag_enabled?
        corpus_version = ::Ai::Rag::Corpus::StateService.call.corpus_version
        key = CacheKeys.retrieval(
          message: message,
          agent_key: agent_key,
          graph_enabled: graph,
          vector_enabled: vector,
          doc_version: corpus_version
        )
        bypass = CachePolicy.bypass?

        result = CacheFetcher.fetch(key: key, category: :retrieval, bypass: bypass) do
          raw = ::Ai::Rag::RetrievalService.call(
            message,
            agent_key: agent_key,
            max_context_chars: max_context_chars,
            max_sections: max_sections,
            max_citations: max_citations
          )
          {
            context_text: raw[:context_text],
            citations: raw[:citations],
            context_truncated: raw[:context_truncated],
            final_context_chars: raw[:final_context_chars],
            final_sections_count: raw[:final_sections_count],
            dropped_section_ids_count: raw[:dropped_section_ids_count],
            # Some tests/stubs only provide a subset of retrieval fields.
            # Treat missing included_section_ids as empty rather than raising.
            included_section_ids: Array(raw[:included_section_ids]),
            # Forward retrieval debug payload for AI_DEBUG dashboards.
            debug: raw[:debug]
          }
        end

        return result if result.is_a?(Hash) && result.key?(:context_text)
        result
      end
    end
  end
end
