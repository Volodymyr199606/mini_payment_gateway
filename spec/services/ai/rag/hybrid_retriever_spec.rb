# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Rag::HybridRetriever do
  let(:fixtures_path) { Rails.root.join('spec/fixtures/context_graph_docs') }
  let(:graph) { Ai::Rag::ContextGraph.new(docs_path: fixtures_path).build }

  def slugify(text)
    text.to_s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-|-\z/, '')
  end

  def section_id(file, heading)
    "#{file}##{slugify(heading)}"
  end

  describe 'merge, dedup, and rerank' do
    it 'merges keyword and vector results and deduplicates by section_id' do
      # Keyword returns Section One and Section Two (from parent.md)
      parent_file = 'spec/fixtures/context_graph_docs/parent.md'
      keyword_hits = [
        { file: parent_file, heading: 'Section One', content: 'Content one.' },
        { file: parent_file, heading: 'Section Two', content: 'Content two.' }
      ]
      kw = instance_double(Ai::Rag::DocsIndex)
      allow(kw).to receive(:search).with(anything, anything).and_return(keyword_hits)

      # Vector returns Section Two (overlap) and Parent Doc (vector-only)
      section_two_id = section_id(parent_file, 'Section Two')
      parent_doc_id = section_id(parent_file, 'Parent Doc')
      vector_store = instance_double('VectorStore', nearest: [[section_two_id, 0.1], [parent_doc_id, 0.2]])

      embed_client = instance_double(Ai::Rag::EmbeddingClient)
      stub_vec = Array.new(Ai::Rag::EmbeddingClient::DIMENSIONS, 0.0)
      allow(embed_client).to receive(:embed).and_return(stub_vec)

      retriever = described_class.new(
        'query',
        keyword_retriever: kw,
        embedding_client: embed_client,
        graph: graph,
        vector_store: vector_store
      )
      result = retriever.call

      expect(result).to have_key(:sections)
      expect(result).to have_key(:seed_ids)
      section_ids = result[:sections].map { |s| s[:id] }
      expect(section_ids).to eq(section_ids.uniq), 'sections must be deduplicated'
      # Should include both keyword (Section One, Section Two) and vector (Parent Doc)
      expect(section_ids).to include(section_id(parent_file, 'Section One'))
      expect(section_ids).to include(section_two_id)
      expect(section_ids).to include(parent_doc_id)
    end

    it 'reranks so sections appearing in both keyword and vector lists rank higher' do
      parent_file = 'spec/fixtures/context_graph_docs/parent.md'
      section_one_id = section_id(parent_file, 'Section One')
      section_two_id = section_id(parent_file, 'Section Two')
      parent_doc_id = section_id(parent_file, 'Parent Doc')

      # Keyword order: Section One, Section Two
      keyword_hits = [
        { file: parent_file, heading: 'Section One', content: 'one' },
        { file: parent_file, heading: 'Section Two', content: 'two' }
      ]
      kw = instance_double(Ai::Rag::DocsIndex)
      allow(kw).to receive(:search).with(anything, anything).and_return(keyword_hits)

      # Vector order: Section Two first, then Parent Doc (so Section Two appears in both)
      vector_store = instance_double('VectorStore', nearest: [[section_two_id, 0.05], [parent_doc_id, 0.2]])
      embed_client = instance_double(Ai::Rag::EmbeddingClient)
      allow(embed_client).to receive(:embed).and_return(Array.new(Ai::Rag::EmbeddingClient::DIMENSIONS, 0.0))

      retriever = described_class.new(
        'query',
        keyword_retriever: kw,
        embedding_client: embed_client,
        graph: graph,
        vector_store: vector_store
      )
      result = retriever.call

      # Section Two is in both lists so gets higher RRF score; should be first
      first_id = result[:sections].first[:id]
      expect(first_id).to eq(section_two_id)
    end

    it 'returns sections with content_chunk and citation shape' do
      parent_file = 'spec/fixtures/context_graph_docs/parent.md'
      keyword_hits = [{ file: parent_file, heading: 'Parent Doc', content: 'Parent.' }]
      kw = instance_double(Ai::Rag::DocsIndex)
      allow(kw).to receive(:search).with(anything, anything).and_return(keyword_hits)
      vector_store = instance_double('VectorStore', nearest: [])
      embed_client = instance_double(Ai::Rag::EmbeddingClient)
      allow(embed_client).to receive(:embed).and_return(Array.new(Ai::Rag::EmbeddingClient::DIMENSIONS, 0.0))

      retriever = described_class.new(
        'query',
        keyword_retriever: kw,
        embedding_client: embed_client,
        graph: graph,
        vector_store: vector_store
      )
      result = retriever.call

      expect(result[:sections].size).to be >= 1
      result[:sections].each do |s|
        expect(s).to have_key(:content_chunk)
        expect(s).to have_key(:citation)
        expect(s).to have_key(:id)
        expect(s[:citation]).to include(:file, :heading, :anchor, :excerpt)
      end
      expect(result[:seed_ids]).to be_a(Array)
    end
  end
end
