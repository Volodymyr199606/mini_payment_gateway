# frozen_string_literal: true

module Ai
  module Rag
    module Corpus
      # Clears in-memory doc index and context graph so next retrieval uses fresh docs.
      # Call after doc changes (e.g. from dev tooling or RefreshDocsIndexJob).
      # Cache keys include corpus version; no need to clear Rails.cache manually.
      class RefreshService
        class << self
          def call
            new.call
          end
        end

        def call
          ::Ai::Rag::DocsIndex.reset!
          ::Ai::Rag::ContextGraph.reset!
          StateService.call
        end
      end
    end
  end
end
