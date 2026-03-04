# frozen_string_literal: true

module Ai
  module ContextGraph
    # Builds a Graph from DocsIndex-style sections (file, heading, level, content).
    # Produces nodes with id "#{file}##{anchor}". Edges: parent/child (heading levels),
    # prev/next (same file), links_to (markdown links resolved to corpus).
    class Builder
      LINK_REGEXP = /\[([^\]]*)\]\(([^)]+)\)/.freeze

      def self.build(sections)
        new(sections).build
      end

      def initialize(sections)
        @sections = sections.to_a
      end

      def build
        nodes = {}
        by_file = {}

        sections_by_file.each do |file, sections|
          ancestors = []
          prev_id = nil

          sections.each_with_index do |s, _idx|
            anchor = s[:anchor] || slugify(s[:heading].to_s)
            id = section_id(normalize_file(file), anchor)

            node = {
              id: id,
              file: normalize_file(file),
              heading: s[:heading],
              anchor: anchor,
              level: s[:level].to_i,
              content: s[:content].to_s,
              parent_id: nil,
              children_ids: [],
              prev_id: nil,
              next_id: nil,
              outgoing_link_ids: []
            }

            level = node[:level]
            while ancestors.any? && ancestors.last[0] >= level
              ancestors.pop
            end
            node[:parent_id] = ancestors.last[1] if ancestors.any?
            ancestors << [level, id]

            node[:prev_id] = prev_id
            nodes[prev_id][:next_id] = id if prev_id

            nodes[id] = node
            by_file[node[:file]] ||= []
            by_file[node[:file]] << id
            prev_id = id
          end
        end

        nodes.each_value do |node|
          pid = node[:parent_id]
          nodes[pid][:children_ids] << node[:id] if pid
        end

        nodes.each_value do |node|
          links = extract_links(node[:content], node[:file])
          node[:outgoing_link_ids] = links.map { |target| resolve_link(target, node[:file], nodes, by_file) }.compact.uniq
        end

        Graph.new(nodes)
      end

      private

      def sections_by_file
        @sections.group_by { |s| normalize_file(s[:file]) }
      end

      def slugify(text)
        text.to_s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-|-\z/, '')
      end

      def section_id(file, anchor)
        "#{file}##{anchor}"
      end

      def normalize_file(file)
        file.to_s.gsub('\\', '/')
      end

      def extract_links(content, _current_file)
        return [] if content.blank?
        content.scan(LINK_REGEXP).map { |_text, href| href.strip }.reject { |h| h.start_with?('http://', 'https://', 'mailto:') }
      end

      def resolve_link(href, current_file, nodes, by_file)
        return nil if href.blank?

        path, frag = href.split('#', 2)
        path = path.to_s.strip
        frag = frag.to_s.strip if frag

        if path.present?
          base_dir = File.dirname(current_file).gsub('\\', '/')
          full_path = base_dir == '.' ? path : "#{base_dir}/#{path}"
          full_path = Pathname.new(full_path.gsub('\\', '/')).cleanpath.to_s.gsub('\\', '/')
          full_path = "#{full_path}.md" if File.extname(full_path).empty?
        else
          full_path = current_file
        end

        return nil unless by_file.key?(full_path)

        if frag.present?
          anchor = slugify(frag)
          candidate_id = "#{full_path}##{anchor}"
          return candidate_id if nodes.key?(candidate_id)
          nodes.each_value do |n|
            return n[:id] if n[:file] == full_path && n[:anchor] == anchor
          end
        end

        by_file[full_path]&.first
      end
    end
  end
end
