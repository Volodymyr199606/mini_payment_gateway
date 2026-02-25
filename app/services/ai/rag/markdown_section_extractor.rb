# frozen_string_literal: true

module Ai
  module Rag
    # Parses Markdown content into sections by headings (#, ##, ###).
    # Returns array of hashes: { heading:, level:, content: }
    class MarkdownSectionExtractor
      HEADING_REGEXP = /^(\#{1,6})\s+(.+)$/

      class << self
        def extract(content, file_path: nil)
          new(content, file_path: file_path).extract
        end
      end

      def initialize(content, file_path: nil)
        @content = content.to_s
        @file_path = file_path
      end

      def extract
        sections = []
        current_heading = nil
        current_level = 0
        current_content = []

        @content.each_line do |line|
          if (m = line.match(HEADING_REGEXP))
            flush_section(sections, current_heading, current_level, current_content) if current_heading
            current_level = m[1].length
            current_heading = m[2].strip
            current_content = []
          else
            current_content << line
          end
        end
        flush_section(sections, current_heading, current_level, current_content) if current_heading

        if sections.empty? && @content.present?
          sections << build_section('Document', 1, @content.strip)
        end

        sections
      end

      private

      def flush_section(sections, heading, level, content_lines)
        content = content_lines.join.strip
        sections << build_section(heading, level, content) if heading
      end

      def build_section(heading, level, content)
        h = { heading: heading, level: level, content: content }
        h[:file] = @file_path if @file_path
        h
      end
    end
  end
end
