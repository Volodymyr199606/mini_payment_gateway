# frozen_string_literal: true

module Ai
  module Rag
    # In-memory index of docs/**/*.md parsed into sections by heading.
    class DocsIndex
      MAX_SECTION_CHARS = 1200
      TOKENS_PER_CHAR = 0.25

      class << self
        def instance
          if Rails.env.development?
            mtime = Dir.glob(Rails.root.join('docs/**/*.md')).map { |f| File.mtime(f) }.max
            @instance = nil if @last_mtime && mtime && mtime > @last_mtime
            @last_mtime = mtime
          end
          @instance ||= new.build
        end

        def reset!
          @instance = nil
          @last_mtime = nil
        end
      end

      def initialize
        @docs_path = Rails.root.join('docs')
        @sections = []
      end

      def build
        return self unless @docs_path.exist?

        Dir.glob(@docs_path.join('**/*.md')).each do |path|
          path = Pathname(path) unless path.is_a?(Pathname)
          relative = path.relative_path_from(Rails.root).to_s
          content = File.read(path)
          sections = MarkdownSectionExtractor.extract(content, file_path: relative)
          sections.each do |s|
            content_truncated = s[:content].to_s.truncate(MAX_SECTION_CHARS)
            @sections << {
              file: relative,
              heading: s[:heading],
              level: s[:level],
              content: content_truncated,
              tokens_estimate: (content_truncated.length * TOKENS_PER_CHAR).to_i,
              keywords: extract_keywords(s[:heading].to_s + ' ' + content_truncated)
            }
          end
        end
        self
      end

      def sections
        @sections
      end

      def search(query, top_k: 5)
        terms = query.to_s.downcase.split(/\s+/).reject { |t| t.length < 2 }
        return [] if terms.empty?

        scored = sections.map do |s|
          score = 0
          text = "#{s[:heading]} #{s[:content]}".downcase
          terms.each do |term|
            count = text.scan(/\b#{Regexp.escape(term)}\b/).size
            score += count * 2 if s[:heading].to_s.downcase.include?(term)
            score += count
          end
          [score, s]
        end
        scored.select { |sc, _| sc.positive? }.sort_by { |sc, _| -sc }.first(top_k).map(&:last)
      end

      private

      def extract_keywords(text)
        text.downcase.scan(/\b[a-z0-9]{2,}\b/).uniq
      end
    end
  end
end
