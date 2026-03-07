# frozen_string_literal: true

module Ai
  module Rag
    # Helpers for ai:smoke_hybrid rake: pgvector/table checks, deterministic stub embedding, smoke retrieval.
    module SmokeHybrid
      DIMENSIONS = EmbeddingClient::DIMENSIONS

      class << self
        # Returns true if the pgvector extension is enabled in the current DB.
        def pgvector_enabled?
          return false unless defined?(ActiveRecord)

          row = ActiveRecord::Base.connection.select_one(
            "SELECT 1 AS one FROM pg_extension WHERE extname = 'vector'"
          )
          row.present?
        rescue StandardError
          false
        end

        # Returns true if doc_section_embeddings table exists.
        def doc_section_embeddings_exists?
          return false unless defined?(DocSectionEmbedding)

          DocSectionEmbedding.table_exists?
        rescue StandardError
          false
        end

        # Deterministic 1536-dim vector from a seed (for DRY_RUN backfill). Same seed => same vector.
        def deterministic_embedding_for(seed)
          digest = Digest::SHA256.hexdigest(seed.to_s)
          # Use hex chars to generate reproducible floats in [0,1)
          values = []
          (DIMENSIONS * 4).times do |i|
            idx = i % digest.length
            values << (digest[idx].ord / 256.0)
          end
          values.first(DIMENSIONS).map(&:to_f)
        end

        # Runs one hybrid retrieval with AI_VECTOR_RAG_ENABLED=true and returns summary.
        # Returns { retriever:, sections_count:, citations: (first 3) }.
        def run_smoke_retrieval(query = 'How do I refund a payment?')
          previous = ENV[RetrievalService::VECTOR_RAG_ENV_KEY]
          ENV[RetrievalService::VECTOR_RAG_ENV_KEY] = 'true'
          result = RetrievalService.call(query, agent_key: :support_faq)
          retriever = result[:debug]&.dig(:retriever).presence || 'HybridRetriever'
          citations = result[:citations].to_a.first(3)
          {
            retriever: retriever,
            sections_count: result[:citations]&.size || 0,
            citations: citations
          }
        ensure
          ENV[RetrievalService::VECTOR_RAG_ENV_KEY] = previous
        end
      end
    end
  end
end
