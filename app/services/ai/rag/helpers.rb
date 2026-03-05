# frozen_string_literal: true

module Ai
  module Rag
    # Shared helpers for section ids and citations across DocsRetriever, GraphExpandedRetriever, HybridRetriever.
    module Helpers
      EXCERPT_LENGTH = 160

      class << self
        # Normalize path separators to forward slashes (e.g. Windows backslashes).
        def normalize_file(path)
          path.to_s.gsub('\\', '/')
        end

        # Slug for anchor links: lowercase, non-alphanumeric replaced with single hyphen, no leading/trailing hyphen.
        def slugify_heading(text)
          text.to_s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-|-\z/, '')
        end

        # Build section id string: "file#anchor" (file should be normalized).
        def section_id(file, anchor)
          "#{file}##{anchor}"
        end

        # Build citation hash for a section. Section is a hash with :file, :heading, :content; optional :anchor.
        # Returns { file:, heading:, anchor:, excerpt: } with file normalized and excerpt truncated.
        def build_citation(section)
          file = normalize_file(section[:file])
          heading = section[:heading]
          content = section[:content].to_s
          anchor = section[:anchor] || slugify_heading(section[:heading].to_s)
          {
            file: file,
            heading: heading,
            anchor: anchor,
            excerpt: content.truncate(EXCERPT_LENGTH)
          }
        end
      end
    end
  end
end
