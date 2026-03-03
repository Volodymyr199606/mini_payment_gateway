# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Rag::ContextGraph do
  let(:fixtures_path) { Rails.root.join('spec/fixtures/context_graph_docs') }
  let(:graph) { described_class.new(docs_path: fixtures_path).build }

  before { described_class.reset! }

  describe '#build' do
    it 'builds nodes from docs' do
      expect(graph.nodes.size).to be >= 4
      ids = graph.nodes.map { |n| n[:id] }
      expect(ids.any? { |id| id.include?('parent-doc') }).to be true
      expect(ids.any? { |id| id.include?('section-one') }).to be true
      expect(ids.any? { |id| id.include?('child-doc') }).to be true
    end

    it 'creates parent/child edges from heading hierarchy' do
      parent_doc = graph.nodes.find { |n| n[:heading] == 'Parent Doc' }
      expect(parent_doc).to be_present
      expect(parent_doc[:level]).to eq(1)
      expect(parent_doc[:parent_id]).to be_nil

      section_one = graph.nodes.find { |n| n[:heading] == 'Section One' }
      expect(section_one).to be_present
      expect(section_one[:parent_id]).to eq(parent_doc[:id])
      expect(parent_doc[:children_ids]).to include(section_one[:id])

      subsection = graph.nodes.find { |n| n[:heading] == 'Subsection' }
      expect(subsection).to be_present
      expect(subsection[:level]).to eq(3)
      section_two = graph.nodes.find { |n| n[:heading] == 'Section Two' }
      expect(subsection[:parent_id]).to eq(section_two[:id])
    end

    it 'creates prev/next neighbor edges' do
      section_one = graph.nodes.find { |n| n[:heading] == 'Section One' }
      section_two = graph.nodes.find { |n| n[:heading] == 'Section Two' }
      expect(section_one[:next_id]).to eq(section_two[:id])
      expect(section_two[:prev_id]).to eq(section_one[:id])
    end

    it 'extracts links from markdown content' do
      section_one = graph.nodes.find { |n| n[:heading] == 'Section One' }
      expect(section_one[:content]).to include('[child.md](child.md)')
      child_main = graph.nodes.find { |n| n[:file].include?('child') && n[:heading] == 'Main' }
      expect(child_main).to be_present
    end

    it 'resolves cross-file links when target exists in graph' do
      # Use real docs: PAYMENT_LIFECYCLE links to TIMEOUTS.md
      real_graph = described_class.instance
      auth_section = real_graph.nodes.find { |n| n[:file]&.include?('PAYMENT_LIFECYCLE') && n[:content]&.include?('TIMEOUTS.md') }
      skip 'PAYMENT_LIFECYCLE not found' unless auth_section
      expect(auth_section[:outgoing_link_ids]).not_to be_empty
    end
  end

  describe '#expand' do
    it 'returns deterministic ordered list including seeds' do
      section_one = graph.nodes.find { |n| n[:heading] == 'Section One' }
      seed_ids = [section_one[:id]]
      result = graph.expand(seed_ids, max_hops: 1, max_nodes: 6)
      expect(result).to include(section_one[:id])
      expect(result.size).to be <= 6
      expect(result).to eq(result.uniq)
    end

    it 'includes parent, prev, next, and link targets' do
      section_one = graph.nodes.find { |n| n[:heading] == 'Section One' }
      seed_ids = [section_one[:id]]
      result = graph.expand(seed_ids, max_hops: 1, max_nodes: 10)
      parent_doc = graph.nodes.find { |n| n[:heading] == 'Parent Doc' }
      section_two = graph.nodes.find { |n| n[:heading] == 'Section Two' }
      expect(result).to include(section_one[:id])
      expect(result).to include(parent_doc[:id])
      expect(result).to include(section_two[:id])
    end

    it 'stops at max_nodes' do
      section_one = graph.nodes.find { |n| n[:heading] == 'Section One' }
      result = graph.expand([section_one[:id]], max_nodes: 3)
      expect(result.size).to eq(3)
    end

    it 'returns empty for empty seeds' do
      expect(graph.expand([])).to eq([])
      expect(graph.expand(nil)).to eq([])
    end
  end

  describe 'section_id format' do
    it 'uses file#anchor format' do
      node = graph.nodes.first
      expect(node[:id]).to match(/.+\.md#.+/)
      expect(node[:id]).to include(node[:file])
      expect(node[:id]).to include(node[:anchor])
    end
  end
end
