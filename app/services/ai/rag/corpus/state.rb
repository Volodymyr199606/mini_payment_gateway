# frozen_string_literal: true

module Ai
  module Rag
    module Corpus
      # Immutable snapshot of corpus metadata: version, counts, flags. Safe for debug/observability.
      State = Struct.new(
        :corpus_version,
        :docs_count,
        :last_changed_at,
        :graph_enabled,
        :vector_enabled,
        :last_indexed_at,
        :stale,
        keyword_init: true
      ) do
        def self.empty
          new(
            corpus_version: 'v0',
            docs_count: 0,
            last_changed_at: nil,
            graph_enabled: false,
            vector_enabled: false,
            last_indexed_at: nil,
            stale: false
          )
        end

        def to_h
          {
            corpus_version: corpus_version,
            docs_count: docs_count,
            last_changed_at: last_changed_at&.iso8601,
            graph_enabled: graph_enabled,
            vector_enabled: vector_enabled,
            last_indexed_at: last_indexed_at&.iso8601,
            stale: stale
          }.compact
        end
      end
    end
  end
end
