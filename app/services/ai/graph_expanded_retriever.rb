# frozen_string_literal: true

module Ai
  # Wraps a keyword retriever and expands results via the doc context graph.
  # Algorithm: seed with keyword top_k → expand each seed (parent, children, links, prev/next)
  # → score heuristics → de-duplicate → return top_k sections with citations.
  class GraphExpandedRetriever
    SEED_K = 4
    FINAL_TOP_K = 6
    EXPANSION_CAP_PER_SEED = 10
    MAX_CONTEXT_CHARS = 5000
    MAX_CHARS_PER_SECTION = 1000
    EXCERPT_LENGTH = 160

    # Score tiers (higher = better). Used for ordering after dedup.
    SCORE_SEED = 100
    SCORE_SAME_FILE_PARENT_CHILD = 80
    SCORE_LINKS_TO = 50
    SCORE_NEIGHBOR = 30

    def initialize(query, keyword_retriever: nil, graph: nil)
      @query = query.to_s
      @keyword_retriever = keyword_retriever || default_keyword_retriever
      @graph = graph || default_graph
    end

    # Returns { context_text:, citations:, seed_count:, expanded_count:, final_count: }
    # (seed_count/expanded_count/final_count are for logging; consumers may ignore them.)
    def call
      seed_ids = fetch_seed_ids
      return empty_result_with_meta(0, 0, 0) if seed_ids.empty?

      scored = expand_and_score(seed_ids)
      ordered = dedupe_keep_best_score(scored)
      top_ids = ordered.first(FINAL_TOP_K).map { |_score, id| id }
      all_unique_ids = ordered.map { |_s, id| id.to_s }.uniq
      expanded_count = (all_unique_ids - seed_ids.map(&:to_s)).size
      result = build_result(top_ids)
      result.merge(
        seed_count: seed_ids.size,
        expanded_count: expanded_count,
        final_count: result[:citations].size
      )
    end

    private

    def default_keyword_retriever
      Rag::DocsIndex.instance
    end

    def default_graph
      Rag::ContextGraph.instance
    end

    def fetch_seed_ids
      hits = @keyword_retriever.search(@query, top_k: SEED_K)
      hits.map { |s| section_id(normalize_file(s[:file]), slugify(s[:heading].to_s)) }.uniq
    end

    def expand_and_score(seed_ids)
      # id => best score seen
      scores = {}
      seed_ids.each { |id| scores[id] = [SCORE_SEED, id] }

      seed_ids.each do |sid|
        node = @graph.node(sid)
        next unless node

        expanded = expand_one_seed(node)
        expanded.each do |nid, edge_type|
          score = score_for_edge_type(edge_type, node, nid)
          existing = scores[nid]
          # Keep higher score when de-duplicating
          scores[nid] = [score, nid] if existing.nil? || score > existing[0]
        end
      end

      scores.values
    end

    # Returns array of [node_id, edge_type] with cap per seed.
    def expand_one_seed(node)
      out = []
      sid = node[:id]
      cap = EXPANSION_CAP_PER_SEED

      # Parent (1)
      if node[:parent_id] && out.size < cap
        out << [node[:parent_id], :parent]
      end

      # Children (1 level)
      node[:children_ids].to_a.first(cap - out.size).each do |cid|
        break if out.size >= cap
        out << [cid, :child]
      end

      # Prev (1), Next (1)
      if node[:prev_id] && out.size < cap
        out << [node[:prev_id], :prev]
      end
      if node[:next_id] && out.size < cap
        out << [node[:next_id], :next]
      end

      # Links (up to 2)
      node[:outgoing_link_ids].to_a.first(2).each do |lid|
        break if out.size >= cap
        out << [lid, :links_to]
      end

      out
    end

    def score_for_edge_type(edge_type, source_node, target_id)
      target = @graph.node(target_id)
      same_file = target && source_node[:file] == target[:file]

      case edge_type
      when :parent, :child
        same_file ? SCORE_SAME_FILE_PARENT_CHILD : SCORE_NEIGHBOR
      when :links_to
        SCORE_LINKS_TO
      when :prev, :next
        SCORE_NEIGHBOR
      else
        SCORE_NEIGHBOR
      end
    end

    def dedupe_keep_best_score(scored_list)
      # scored_list = [[score, id], ...]; keep max score per id, then sort by score desc
      by_id = scored_list.each_with_object({}) do |(score, id), h|
        id = id.to_s
        h[id] = [score, id] if h[id].nil? || score > h[id][0]
      end
      by_id.values.sort_by { |score, _| -score }
    end

    def build_result(ids)
      context_parts = []
      citations = []
      total_chars = 0

      ids.each do |sid|
        break if total_chars >= MAX_CONTEXT_CHARS
        node = @graph.node(sid)
        next unless node

        content = node[:content].to_s.truncate(MAX_CHARS_PER_SECTION)
        header = "## #{node[:heading]} (#{node[:file]}##{node[:anchor]})"
        chunk = "#{header}\n#{content}"
        remaining = MAX_CONTEXT_CHARS - total_chars
        if chunk.length > remaining
          content = content.truncate([MAX_CHARS_PER_SECTION, remaining - header.length - 2].min)
          chunk = "#{header}\n#{content}"
        end
        total_chars += chunk.length
        context_parts << chunk
        citations << build_citation(node)
      end

      context_text = context_parts.join("\n\n").presence || nil
      { context_text: context_text, citations: citations }
    end

    def build_citation(node)
      {
        file: node[:file],
        heading: node[:heading],
        anchor: node[:anchor],
        excerpt: node[:content].to_s.truncate(EXCERPT_LENGTH)
      }
    end

    def empty_result
      { context_text: nil, citations: [] }
    end

    def empty_result_with_meta(seed_count, expanded_count, final_count)
      empty_result.merge(seed_count: seed_count, expanded_count: expanded_count, final_count: final_count)
    end

    def section_id(file, anchor)
      "#{file}##{anchor}"
    end

    def normalize_file(file)
      file.to_s.gsub('\\', '/')
    end

    def slugify(text)
      text.to_s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-|-\z/, '')
    end
  end
end
