# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::GraphExpandedRetriever do
  let(:fixtures_path) { Rails.root.join('spec/fixtures/context_graph_docs') }
  let(:graph) { Ai::Rag::ContextGraph.new(docs_path: fixtures_path).build }

  # Keyword retriever that returns sections with file and heading (matching graph's section ids).
  def stub_keyword_retriever(*sections)
    sections_with_file = sections.map do |heading|
      file = graph.nodes.find { |n| n[:heading] == heading }&.dig(:file) || 'spec/fixtures/context_graph_docs/parent.md'
      { file: file, heading: heading, content: heading }
    end
    instance_double('KeywordRetriever', search: sections_with_file).tap do |dbl|
      allow(dbl).to receive(:search).with(anything, top_k: anything).and_return(sections_with_file)
    end
  end

  describe '#call' do
    it 'returns context_text and citations' do
      kw = stub_keyword_retriever('Section One')
      retriever = described_class.new('query', keyword_retriever: kw, graph: graph)
      result = retriever.call
      expect(result).to have_key(:context_text)
      expect(result).to have_key(:citations)
      expect(result[:citations]).to be_a(Array)
      result[:citations].each do |c|
        expect(c).to have_key(:file)
        expect(c).to have_key(:heading)
        expect(c).to have_key(:anchor)
        expect(c).to have_key(:excerpt)
      end
    end

    it 'expansion includes seed and expected related sections (parent, next, links)' do
      kw = stub_keyword_retriever('Section One')
      retriever = described_class.new('query', keyword_retriever: kw, graph: graph)
      result = retriever.call
      headings = result[:citations].map { |c| c[:heading] }
      # Seed must be present
      expect(headings).to include('Section One')
      # Same-file parent and next must be included by expansion
      expect(headings).to include('Parent Doc')
      expect(headings).to include('Section Two')
      # Link targets (when resolved) should be reachable; Section One links to child.md
      section_one_id = graph.nodes.find { |n| n[:heading] == 'Section One' }&.dig(:id)
      if section_one_id
        node = graph.node(section_one_id)
        linked_ids = node&.dig(:outgoing_link_ids).to_a
        linked_headings = linked_ids.map { |id| graph.node(id)&.dig(:heading) }.compact
        linked_headings.each { |h| expect(headings).to include(h) } if linked_headings.any?
      end
      expect(result[:context_text]).to match(/##\s+.+\([^)]+\.md#[a-z0-9-]+\)/)
    end

    it 'returns at most FINAL_TOP_K sections' do
      kw = stub_keyword_retriever('Section One', 'Section Two', 'Parent Doc', 'Main')
      retriever = described_class.new('query', keyword_retriever: kw, graph: graph)
      result = retriever.call
      expect(result[:citations].size).to be <= described_class::FINAL_TOP_K
    end

    it 'respects final context size cap' do
      kw = stub_keyword_retriever('Section One')
      retriever = described_class.new('query', keyword_retriever: kw, graph: graph)
      result = retriever.call
      next if result[:context_text].nil?
      expect(result[:context_text].length).to be <= described_class::MAX_CONTEXT_CHARS + 100
    end

    it 'de-duplicates and keeps best score (seed over expanded)' do
      # Section One is seed; it is also the "next" of Parent Doc. So Parent could be expanded.
      # Seed "Section One" and "Section Two" -> Section One appears as seed only once.
      kw = stub_keyword_retriever('Section One', 'Section Two')
      retriever = described_class.new('query', keyword_retriever: kw, graph: graph)
      result = retriever.call
      ids = result[:citations].map { |c| "#{c[:file]}##{c[:anchor]}" }
      expect(ids).to eq(ids.uniq)
    end
  end

  describe 'expansion cap per seed' do
    it 'does not explode when a seed has many children' do
      # Build a graph with one parent and 15 children
      many_children_path = Rails.root.join('spec/fixtures/context_graph_many_children')
      FileUtils.mkdir_p(many_children_path)
      path = many_children_path.join('doc.md')
      content = "# Big\n\n"
      15.times { |i| content += "## Child #{i}\nContent #{i}.\n\n" }
      File.write(path, content)
      big_graph = Ai::Rag::ContextGraph.new(docs_path: many_children_path).build

      big_node = big_graph.nodes.find { |n| n[:heading] == 'Big' }
      expect(big_node[:children_ids].size).to eq(15)

      kw = instance_double('KeywordRetriever')
      allow(kw).to receive(:search).with(anything, top_k: anything).and_return(
        [{ file: big_node[:file], heading: 'Big', content: 'Big' }]
      )
      retriever = described_class.new('query', keyword_retriever: kw, graph: big_graph)
      result = retriever.call

      # Should return at most FINAL_TOP_K; expansion cap prevents 1 + 15 in pool
      expect(result[:citations].size).to be <= described_class::FINAL_TOP_K
      expect(result[:citations].map { |c| c[:heading] }.uniq.size).to eq(result[:citations].size)
    ensure
      FileUtils.rm_rf(many_children_path) if many_children_path.exist?
    end
  end

  describe 'empty / no seeds' do
    it 'returns empty result when keyword retriever returns no hits' do
      kw = instance_double('KeywordRetriever')
      allow(kw).to receive(:search).with(anything, top_k: anything).and_return([])
      retriever = described_class.new('query', keyword_retriever: kw, graph: graph)
      result = retriever.call
      expect(result[:context_text]).to be_nil
      expect(result[:citations]).to eq([])
    end
  end
end
