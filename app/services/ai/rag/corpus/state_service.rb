# frozen_string_literal: true

module Ai
  module Rag
    module Corpus
      # Reports current RAG corpus state for retrieval, cache keys, debug, and internal dashboards.
      class StateService
        class << self
          def call
            new.call
          end
        end

        def initialize(docs_root: nil)
          @docs_root = docs_root || Rails.root
        end

        def call
          resolver = VersionResolver.new(docs_root: @docs_root)
          version = resolver.resolve
          entries = resolver.collect_entries
          last_changed = resolver.last_changed_at

          State.new(
            corpus_version: version,
            docs_count: entries.size,
            last_changed_at: last_changed,
            graph_enabled: graph_enabled?,
            vector_enabled: vector_enabled?,
            last_indexed_at: last_changed,
            stale: false
          )
        end

        private

        def graph_enabled?
          ENV['AI_CONTEXT_GRAPH_ENABLED'].to_s.strip.downcase.in?(%w[true 1])
        end

        def vector_enabled?
          ENV['AI_VECTOR_RAG_ENABLED'].to_s.strip.downcase.in?(%w[true 1])
        end
      end
    end
  end
end
