# frozen_string_literal: true

module Ai
  module Rag
    # Feature-flagged doc retrieval: uses GraphExpandedRetriever when
    # AI_CONTEXT_GRAPH_ENABLED=true, otherwise DocsRetriever (keyword + simple expand).
    # Logs selected retriever and section counts.
    class RetrievalService
      ENV_KEY = 'AI_CONTEXT_GRAPH_ENABLED'

      class << self
        # Returns { context_text:, citations: }. Logs retriever choice and counts.
        def call(message, agent_key: nil)
          if context_graph_enabled?
            result = ::Ai::GraphExpandedRetriever.new(message).call
            log_retrieval(
              retriever: 'GraphExpandedRetriever',
              seed_count: result[:seed_count],
              expanded_count: result[:expanded_count],
              final_count: result[:final_count]
            )
            result.slice(:context_text, :citations)
          else
            result = DocsRetriever.new(message, agent_key: agent_key).call
            log_retrieval(
              retriever: 'DocsRetriever',
              seed_count: nil,
              expanded_count: nil,
              final_count: result[:citations]&.size
            )
            result
          end
        end

        def context_graph_enabled?
          v = ENV[ENV_KEY].to_s.strip.downcase
          v == 'true' || v == '1'
        end

        private

        def log_retrieval(retriever:, seed_count:, expanded_count:, final_count:)
          payload = {
            event: 'ai_doc_retrieval',
            retriever: retriever,
            final_sections_count: final_count
          }
          payload[:seed_sections_count] = seed_count if seed_count
          payload[:expanded_sections_count] = expanded_count if expanded_count
          Rails.logger.info(payload.to_json)
        end
      end
    end
  end
end
