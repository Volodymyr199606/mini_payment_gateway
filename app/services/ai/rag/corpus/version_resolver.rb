# frozen_string_literal: true

module Ai
  module Rag
    module Corpus
      # Resolves a stable corpus version from docs/**/*.md. Version changes when any doc
      # path or mtime changes. Used for cache keys and corpus state.
      class VersionResolver
        DOCS_GLOB = 'docs/**/*.md'
        VERSION_LEN = 12

        class << self
          def resolve(docs_root: nil)
            new(docs_root: docs_root).resolve
          end
        end

        def initialize(docs_root: nil)
          @docs_root = docs_root || Rails.root
        end

        # Returns a short hex string that changes when any doc is added/removed/updated.
        def resolve
          entries = collect_entries
          return 'v0' if entries.empty?

          raw = entries.sort_by { |e| e[:path] }.map { |e| "#{e[:path]}:#{e[:mtime].to_i}" }.join('|')
          Digest::SHA256.hexdigest(raw)[0, VERSION_LEN]
        end

        # Returns [{ path:, mtime: }] for each .md file (relative to Rails.root).
        def collect_entries
          pattern = @docs_root.join(DOCS_GLOB).to_s
          Dir.glob(pattern).filter_map do |path|
            relative = Pathname(path).relative_path_from(@docs_root).to_s.gsub('\\', '/')
            { path: relative, mtime: File.mtime(path) }
          end
        end

        # Latest mtime among all docs; nil if no docs.
        def last_changed_at
          entries = collect_entries
          return nil if entries.empty?

          entries.map { |e| e[:mtime] }.max
        end
      end
    end
  end
end
