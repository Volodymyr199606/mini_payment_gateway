# frozen_string_literal: true

module Ai
  module Rag
    # Canonical production context graph for RAG. Use this (not Ai::ContextGraph::Builder/Graph).
    # Context graph over doc sections: models document structure for RAG expansion.
    # Nodes = sections (file + heading + anchor). Edges = parent/child, prev/next, cross-links.
    # Section id format: "docs/PAYMENT_LIFECYCLE.md#authorize-in-this-project"
    #
    # API: .instance / .reset! ; #node(section_id) ; #expand(seed_ids, max_hops:, max_nodes:) ; #nodes
    class ContextGraph
      # Markdown link: [text](path) or [text](path#anchor)
      LINK_REGEXP = /\[([^\]]*)\]\(([^)]+)\)/.freeze

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

      def initialize(docs_path: nil)
        @docs_path = docs_path ? Pathname(docs_path) : Rails.root.join('docs')
        @nodes = {}     # id => { id, file, heading, anchor, level, content, parent_id, children_ids, prev_id, next_id, outgoing_link_ids }
        @by_file = {}   # file => [node_ids in order]
      end

      def build
        return self unless @docs_path.exist?

        sections_by_file = {}
        Dir.glob(@docs_path.join('**/*.md')).each do |path|
          path = Pathname(path) unless path.is_a?(Pathname)
          relative = path.relative_path_from(Rails.root).to_s.gsub('\\', '/')
          content = File.read(path)
          sections = MarkdownSectionExtractor.extract(content, file_path: relative)
          sections_by_file[relative] = sections
        end

        # Build nodes and parent/child, prev/next
        sections_by_file.each do |file, sections|
          ancestors = [] # stack of [level, node_id] for parent resolution
          prev_id = nil

          sections.each_with_index do |s, idx|
            anchor = slugify(s[:heading].to_s)
            id = section_id(file, anchor)
            node = {
              id: id,
              file: file,
              heading: s[:heading],
              anchor: anchor,
              level: s[:level],
              content: s[:content].to_s,
              parent_id: nil,
              children_ids: [],
              prev_id: nil,
              next_id: nil,
              outgoing_link_ids: []
            }

            # Parent: pop ancestors until we find one with level < current
            while ancestors.any? && ancestors.last[0] >= s[:level]
              ancestors.pop
            end
            node[:parent_id] = ancestors.last[1] if ancestors.any?
            ancestors << [s[:level], id]

            node[:prev_id] = prev_id
            @nodes[prev_id][:next_id] = id if prev_id

            @nodes[id] = node
            @by_file[file] ||= []
            @by_file[file] << id
            prev_id = id
          end
        end

        # Set children_ids
        @nodes.each_value do |node|
          pid = node[:parent_id]
          @nodes[pid][:children_ids] << node[:id] if pid
        end

        # Extract cross-links and resolve to node ids
        @nodes.each_value do |node|
          links = extract_links(node[:content], node[:file])
          node[:outgoing_link_ids] = links.map { |target| resolve_link(target, node[:file]) }.compact.uniq
        end

        self
      end

      # Expansion: include seeds + parents, prev/next, up to 2 outgoing links per seed. Stop at max_nodes.
      def expand(seed_section_ids, max_hops: 1, max_nodes: 6)
        seeds = Array(seed_section_ids).map(&:to_s).reject(&:blank?)
        return [] if seeds.empty?

        ids = seeds.dup
        added = seeds.to_set

        seeds.each do |sid|
          break if ids.size >= max_nodes
          node = @nodes[sid]
          next unless node

          # Add parent
          if node[:parent_id] && !added.include?(node[:parent_id])
            ids << node[:parent_id]
            added << node[:parent_id]
            break if ids.size >= max_nodes
          end

          # Add prev
          if node[:prev_id] && !added.include?(node[:prev_id])
            ids << node[:prev_id]
            added << node[:prev_id]
            break if ids.size >= max_nodes
          end

          # Add next
          if node[:next_id] && !added.include?(node[:next_id])
            ids << node[:next_id]
            added << node[:next_id]
            break if ids.size >= max_nodes
          end

          # Add up to 2 outgoing links
          node[:outgoing_link_ids].first(2).each do |lid|
            break if ids.size >= max_nodes
            next if added.include?(lid)
            ids << lid
            added << lid
          end
        end

        ids.first(max_nodes)
      end

      def node(id)
        @nodes[id.to_s]
      end

      def nodes
        @nodes.values
      end

      def section_id(file, anchor)
        "#{file}##{anchor}"
      end

      private

      def slugify(text)
        text.to_s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-|-\z/, '')
      end

      def extract_links(content, current_file)
        return [] if content.blank?
        content.scan(LINK_REGEXP).map do |_text, href|
          href.strip
        end.reject { |h| h.start_with?('http://', 'https://', 'mailto:') }
      end

      # Resolve href to a node id. href can be "TIMEOUTS.md", "docs/TIMEOUTS.md", "docs/TIMEOUTS.md#section"
      def resolve_link(href, current_file)
        return nil if href.blank?

        path, frag = href.split('#', 2)
        path = path.to_s.strip
        frag = frag.to_s.strip if frag

        # Resolve path relative to current file
        if path.present?
          if path.start_with?('docs/')
            full_path = path
          else
            base_dir = File.dirname(current_file).gsub('\\', '/')
            full_path = (base_dir == '.' ? path : "#{base_dir}/#{path}")
            full_path = Pathname.new(full_path.gsub('\\', '/')).cleanpath.to_s.gsub('\\', '/')
            full_path = "docs/#{full_path}" unless full_path.start_with?('docs/')
          end
          full_path = "#{full_path}.md" if File.extname(full_path).empty?
        else
          full_path = current_file
        end

        # Check file exists in our index
        return nil unless @by_file.key?(full_path)

        if frag.present?
          anchor = slugify(frag)
          candidate_id = "#{full_path}##{anchor}"
          return candidate_id if @nodes.key?(candidate_id)
          # Try exact fragment match
          @nodes.each_value do |n|
            return n[:id] if n[:file] == full_path && slugify(n[:heading]) == anchor
          end
        end

        # No anchor: use first section of file
        first_id = @by_file[full_path]&.first
        first_id
      end
    end
  end
end
