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
      DEFAULT_MAX_CONTEXT_CHARS = 5000

      class << self
        # Returns { context_text:, citations:, context_truncated: }. When AI_DEBUG=true adds :debug.
        # Retrievers (additive): graph when AI_CONTEXT_GRAPH_ENABLED; else vector hybrid when AI_VECTOR_RAG_ENABLED; else keyword DocsRetriever.
        def call(message, agent_key: nil, max_context_chars: DEFAULT_MAX_CONTEXT_CHARS)
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

          out = apply_context_budget(raw[:sections], raw[:seed_ids], max_context_chars)
          citations_count = out[:citations]&.size || 0
          context_len = out[:context_text].to_s.length
          ::Ai::Observability::EventLogger.log_retrieval(
            retriever: retriever_name,
            query: message,
            agent_key: agent_key,
            seed_sections_count: raw[:seed_count],
            expanded_sections_count: raw[:expanded_count],
            vector_hits_count: raw[:vector_hits_count],
            final_sections_count: citations_count,
            context_text_length: context_len,
            context_truncated: out[:context_truncated],
            citations_count: citations_count,
            request_id: Thread.current[:ai_request_id]
          )

          if ai_debug?
            all_section_ids = raw[:sections].to_a.map { |s| s[:id] }.compact.map(&:to_s)
            seed_ids = (raw[:seed_ids] || []).map(&:to_s)
            debug = {
              retriever: retriever_name,
              seed_section_ids: raw[:seed_ids].to_a,
              expanded_section_ids: all_section_ids - seed_ids,
              final_included_section_ids: out[:included_section_ids].to_a,
              context_budget_used: out[:context_text].to_s.length,
              max_context_chars: max_context_chars,
              context_truncated: out[:context_truncated]
            }
            debug[:expanded_with_edges] = raw[:expanded_with_edges] if raw[:expanded_with_edges].present?
            out[:debug] = debug
          end
          out.delete(:included_section_ids)
          out
        end

        def ai_debug?
          v = ENV[DEBUG_ENV_KEY].to_s.strip.downcase
          v == 'true' || v == '1'
        end

        def context_graph_enabled?
          v = ENV[ENV_KEY].to_s.strip.downcase
          v == 'true' || v == '1'
        end

        def vector_rag_enabled?
          v = ENV[VECTOR_RAG_ENV_KEY].to_s.strip.downcase
          v == 'true' || v == '1'
        end

        # Include sections in ranked order until budget; always include top seed. Truncate rest.
        # Returns { context_text:, citations:, context_truncated: }.
        def apply_context_budget(sections, seed_ids, max_context_chars)
          sections = sections.to_a
          return { context_text: nil, citations: [], context_truncated: false } if sections.empty?

          seed_set = (seed_ids || []).to_set
          included = []
          budget_remaining = max_context_chars
          context_truncated = false

          # Always include first section (top-ranked / top seed); truncate if over budget
          first = sections.first.dup
          first_chunk = first[:content_chunk].to_s
          if first_chunk.length > max_context_chars
            first[:content_chunk] = first_chunk.truncate(max_context_chars)
            context_truncated = true
          end
          included << first
          budget_remaining -= first[:content_chunk].length

          sections.drop(1).each do |sec|
            chunk = sec[:content_chunk].to_s
            len = chunk.length
            if len <= budget_remaining
              included << sec
              budget_remaining -= len
            else
              context_truncated = true
              break
            end
          end

          context_text = included.map { |s| s[:content_chunk] }.join("\n\n").presence
          citations = included.map { |s| s[:citation] }
          included_section_ids = included.map { |s| s[:id] }
          {
            context_text: context_text,
            citations: citations,
            context_truncated: context_truncated,
            included_section_ids: included_section_ids
          }
        end

      end
    end
  end
end
