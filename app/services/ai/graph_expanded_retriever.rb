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

    # Returns { sections:, seed_ids:, seed_count:, expanded_count: }. When AI_DEBUG adds expanded_with_edges.
    # Each section: { content_chunk:, citation:, id: }.
    def call
      seed_ids = fetch_seed_ids
      return empty_sections_result(seed_ids.size) if seed_ids.empty?

      scored, expanded_with_edges = expand_and_score_with_edges(seed_ids)
      ordered = dedupe_keep_best_score(scored)
      top_ids = ordered.first(FINAL_TOP_K).map { |_score, id| id }
      all_unique_ids = ordered.map { |_s, id| id.to_s }.uniq
      expanded_count = (all_unique_ids - seed_ids.map(&:to_s)).size
      sections = build_sections(top_ids)
      out = {
        sections: sections,
        seed_ids: seed_ids,
        seed_count: seed_ids.size,
        expanded_count: expanded_count
      }
      out[:expanded_with_edges] = expanded_with_edges if ai_debug? && expanded_with_edges.present?
      out
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
      hits.map { |s| Rag::Helpers.section_id(Rag::Helpers.normalize_file(s[:file]), Rag::Helpers.slugify_heading(s[:heading].to_s)) }.uniq
    end

    def expand_and_score(seed_ids)
      expand_and_score_with_edges(seed_ids).first
    end

    # Returns [scored_list, expanded_with_edges]. expanded_with_edges is [[section_id, edge_type], ...] for debug.
    def expand_and_score_with_edges(seed_ids)
      scores = {}
      seed_ids.each { |id| scores[id] = [SCORE_SEED, id] }
      expanded_with_edges = [] if ai_debug?

      seed_ids.each do |sid|
        node = @graph.node(sid)
        next unless node

        expand_one_seed(node).each do |nid, edge_type|
          expanded_with_edges << [nid.to_s, edge_type.to_s] if expanded_with_edges
          score = score_for_edge_type(edge_type, node, nid)
          existing = scores[nid]
          scores[nid] = [score, nid] if existing.nil? || score > existing[0]
        end
      end

      [scores.values, expanded_with_edges || []]
    end

    def ai_debug?
      v = ENV['AI_DEBUG'].to_s.strip.downcase
      v == 'true' || v == '1'
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

    # Returns array of { content_chunk:, citation:, id: } in ranked order (no budget applied).
    def build_sections(ids)
      ids.filter_map do |sid|
        node = @graph.node(sid)
        next unless node

        content = node[:content].to_s.truncate(MAX_CHARS_PER_SECTION)
        header = "## #{node[:heading]} (#{node[:file]}##{node[:anchor]})"
        content_chunk = "#{header}\n#{content}"
        {
          content_chunk: content_chunk,
          citation: Rag::Helpers.build_citation(node),
          id: node[:id]
        }
      end
    end

    def empty_result
      { context_text: nil, citations: [] }
    end

    def empty_sections_result(_seed_count = 0)
      {
        sections: [],
        seed_ids: [],
        seed_count: 0,
        expanded_count: 0
      }
    end

  end
end
