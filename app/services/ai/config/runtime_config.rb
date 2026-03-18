# frozen_string_literal: true

module Ai
  module Config
    # Centralized AI runtime config (numeric/string limits). Complements FeatureFlags.
    module RuntimeConfig
      class << self
        def max_memory_chars
          (ENV['AI_MAX_MEMORY_CHARS'].presence || 4_000).to_i
        end

        def max_recent_messages
          (ENV['AI_MAX_RECENT_MESSAGES'].presence || 10).to_i
        end

        def max_context_chars
          (ENV['AI_MAX_CONTEXT_CHARS'].presence || 12_000).to_i
        end

        def max_retrieved_sections
          (ENV['AI_MAX_RETRIEVED_SECTIONS'].presence || 6).to_i
        end

        def max_citations
          (ENV['AI_MAX_CITATIONS'].presence || 6).to_i
        end

        def cache_doc_version
          ENV['AI_CACHE_DOC_VERSION'].presence || 'v1'
        end
      end
    end
  end
end
