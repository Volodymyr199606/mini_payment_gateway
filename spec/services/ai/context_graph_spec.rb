# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::ContextGraph::Builder do
  let(:fixtures_path) { Rails.root.join('spec/fixtures/context_graph_docs') }

  def load_sections
    sections = []
    Dir.glob(fixtures_path.join('*.md')).each do |path|
      path = Pathname(path)
      relative = path.relative_path_from(Rails.root).to_s.gsub('\\', '/')
      content = File.read(path)
      Ai::Rag::MarkdownSectionExtractor.extract(content, file_path: relative).each do |s|
        sections << s
      end
    end
    sections
  end

  let(:sections) { load_sections }
  let(:graph) { Ai::ContextGraph::Builder.build(sections) }

  describe Ai::ContextGraph::Graph do
    describe '#get' do
      it 'returns section metadata for node_id' do
        section_one = graph.nodes.values.find { |n| n[:heading] == 'Section One' }
        expect(section_one).to be_present
        got = graph.get(section_one[:id])
        expect(got[:file]).to include('parent')
        expect(got[:heading]).to eq('Section One')
        expect(got[:anchor]).to eq('section-one')
        expect(got[:level]).to eq(2)
        expect(got[:content]).to include('child.md')
      end

      it 'returns nil for unknown node_id' do
        expect(graph.get('docs/nonexistent.md#foo')).to be_nil
      end
    end

    describe '#neighbors' do
      it 'returns parent edge from heading hierarchy' do
        section_one = graph.nodes.values.find { |n| n[:heading] == 'Section One' }
        neighbors = graph.neighbors(section_one[:id])
        parent_edge = neighbors.find { |n| n[:edge_type] == :parent }
        expect(parent_edge).to be_present
        expect(graph.get(parent_edge[:node_id])[:heading]).to eq('Parent Doc')
      end

      it 'returns prev/next edges for same-file neighbors' do
        section_one = graph.nodes.values.find { |n| n[:heading] == 'Section One' }
        section_two = graph.nodes.values.find { |n| n[:heading] == 'Section Two' }
        neighbors_one = graph.neighbors(section_one[:id])
        next_edge = neighbors_one.find { |n| n[:edge_type] == :next }
        expect(next_edge).to be_present
        expect(next_edge[:node_id]).to eq(section_two[:id])

        prev_edge = graph.neighbors(section_two[:id]).find { |n| n[:edge_type] == :prev }
        expect(prev_edge[:node_id]).to eq(section_one[:id])
      end

      it 'returns child edges for subsections' do
        section_two = graph.nodes.values.find { |n| n[:heading] == 'Section Two' }
        neighbors = graph.neighbors(section_two[:id])
        child_edges = neighbors.select { |n| n[:edge_type] == :child }
        expect(child_edges.size).to eq(1)
        expect(graph.get(child_edges.first[:node_id])[:heading]).to eq('Subsection')
      end

      it 'returns links_to edges for markdown links' do
        section_one = graph.nodes.values.find { |n| n[:heading] == 'Section One' }
        neighbors = graph.neighbors(section_one[:id])
        link_edges = neighbors.select { |n| n[:edge_type] == :links_to }
        expect(link_edges).not_to be_empty
        linked = graph.get(link_edges.first[:node_id])
        expect(linked[:file]).to include('child')
      end
    end
  end

  describe Ai::ContextGraph::Builder do
    it 'produces nodes with id format file#anchor' do
      expect(graph.nodes.size).to be >= 4
      graph.nodes.each do |id, node|
        expect(id).to match(/.+\.md#.+/)
        expect(id).to include(node[:file])
        expect(id).to include(node[:anchor])
      end
    end

    it 'resolves cross-file links when target exists' do
      subsection = graph.nodes.values.find { |n| n[:heading] == 'Subsection' }
      expect(subsection).to be_present
      expect(subsection[:outgoing_link_ids]).not_to be_empty
      target_id = subsection[:outgoing_link_ids].first
      target = graph.get(target_id)
      expect(target).to be_present
      expect(target[:heading]).to eq('Other')
    end
  end
end
