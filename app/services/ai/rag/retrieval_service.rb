# frozen_string_literal: true

module Ai
  module Rag
    # Feature-flagged doc retrieval: uses GraphExpandedRetriever when
    # AI_CONTEXT_GRAPH_ENABLED=true, otherwise DocsRetriever.
    # Applies deterministic context budgeting; returns context_text, citations (included only), context_truncated.
    class RetrievalService
      ENV_KEY = 'AI_CONTEXT_GRAPH_ENABLED'
      VECTOR_RAG_ENV_KEY = 'AI_VECTOR_RAG_ENABLED'
      DEBUG_ENV_KEY = 'AI_DEBUG'

      class << self
        # Returns { context_text:, citations:, context_truncated:, final_context_chars:, final_sections_count:, dropped_section_ids_count: }. When AI_DEBUG=true adds :debug.
        def call(message, agent_key: nil, max_context_chars: nil, max_sections: nil, max_citations: nil)
          max_context_chars ||= ContextBudgeter.max_context_chars
          max_sections ||= ContextBudgeter.max_sections
          max_citations ||= ContextBudgeter.max_citations

          retriever_name = context_graph_enabled? ? 'GraphExpandedRetriever' : (vector_rag_enabled? ? 'HybridRetriever' : 'DocsRetriever')
          raw = if context_graph_enabled?
            ::Ai::GraphExpandedRetriever.new(message, agent_key: agent_key).call
          elsif vector_rag_enabled?
            r = HybridRetriever.new(message, agent_key: agent_key).call
            { sections: r[:sections], seed_ids: r[:seed_ids], seed_count: nil, expanded_count: nil, vector_hits_count: r[:vector_hits_count] }
          else
            r = DocsRetriever.new(message, agent_key: agent_key).call
            { sections: r[:sections], seed_ids: r[:seed_ids], seed_count: nil, expanded_count: nil }
          end

          out = ContextBudgeter.call(
            raw[:sections],
            max_context_chars: max_context_chars,
            max_sections: max_sections,
            max_citations: max_citations
          )

          ::Ai::Observability::EventLogger.log_retrieval(
            retriever: retriever_name,
            query: message,
            agent_key: agent_key,
            seed_sections_count: raw[:seed_count],
            expanded_sections_count: raw[:expanded_count],
            vector_hits_count: raw[:vector_hits_count],
            final_sections_count: out[:final_sections_count],
            context_text_length: out[:final_context_chars],
            context_truncated: out[:context_truncated],
            citations_count: out[:citations]&.size || 0,
            request_id: Thread.current[:ai_request_id],
            corpus_version: ::Ai::Rag::Corpus::StateService.call.corpus_version
          )

          if ai_debug?
            all_section_ids = raw[:sections].to_a.map { |s| s[:id] }.compact.map(&:to_s)
            seed_ids = (raw[:seed_ids] || []).map(&:to_s)
            debug = {
              retriever: retriever_name,
              seed_section_ids: raw[:seed_ids].to_a,
              expanded_section_ids: all_section_ids - seed_ids,
              final_included_section_ids: out[:included_section_ids].to_a,
              context_budget_used: out[:final_context_chars],
              max_context_chars: max_context_chars,
              context_truncated: out[:context_truncated],
              final_sections_count: out[:final_sections_count],
              dropped_section_ids_count: out[:dropped_section_ids_count]
            }
            debug[:expanded_with_edges] = raw[:expanded_with_edges] if raw[:expanded_with_edges].present?
            out[:debug] = debug
          end
          out
        end

        def ai_debug?
          ::Ai::Config::FeatureFlags.ai_debug_enabled?
        end

        def context_graph_enabled?
          ::Ai::Config::FeatureFlags.ai_graph_retrieval_enabled?
        end

        def vector_rag_enabled?
          ::Ai::Config::FeatureFlags.ai_vector_retrieval_enabled?
        end
      end
    end
  end
end
