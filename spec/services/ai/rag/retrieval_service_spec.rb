# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Rag::RetrievalService do
  def with_env(key, value)
    old = ENV[key]
    ENV[key] = value
    yield
  ensure
    ENV[key] = old
  end

  describe '.context_graph_enabled?' do
    it 'returns true when AI_CONTEXT_GRAPH_ENABLED is true' do
      with_env(described_class::ENV_KEY, 'true') do
        expect(described_class.context_graph_enabled?).to be true
      end
    end

    it 'returns true when AI_CONTEXT_GRAPH_ENABLED is 1' do
      with_env(described_class::ENV_KEY, '1') do
        expect(described_class.context_graph_enabled?).to be true
      end
    end

    it 'returns false when AI_CONTEXT_GRAPH_ENABLED is false' do
      with_env(described_class::ENV_KEY, 'false') do
        expect(described_class.context_graph_enabled?).to be false
      end
    end

    it 'returns false when AI_CONTEXT_GRAPH_ENABLED is unset' do
      with_env(described_class::ENV_KEY, nil) do
        expect(described_class.context_graph_enabled?).to be false
      end
    end
  end

  describe '.vector_rag_enabled?' do
    it 'returns true when AI_VECTOR_RAG_ENABLED is true' do
      with_env(described_class::VECTOR_RAG_ENV_KEY, 'true') do
        expect(described_class.vector_rag_enabled?).to be true
      end
    end

    it 'returns false when AI_VECTOR_RAG_ENABLED is unset' do
      with_env(described_class::VECTOR_RAG_ENV_KEY, nil) do
        expect(described_class.vector_rag_enabled?).to be false
      end
    end
  end

  describe '.call' do
    it 'logs and returns DocsRetriever result when context graph is disabled' do
      with_env(described_class::ENV_KEY, 'false') do
        logged = nil
        allow(Rails.logger).to receive(:info) { |arg| logged = arg }
        result = described_class.call('refund', agent_key: :operational)
        expect(result).to have_key(:context_text)
        expect(result).to have_key(:citations)
        expect(result[:citations]).to be_a(Array)
        parsed = JSON.parse(logged)
        expect(parsed['event']).to eq('ai_doc_retrieval')
        expect(parsed['retriever']).to eq('DocsRetriever')
        expect(parsed['final_sections_count']).to be_a(Integer)
      end
    end

    it 'uses HybridRetriever when AI_VECTOR_RAG_ENABLED is true and graph is disabled' do
      with_env(described_class::ENV_KEY, 'false') do
        with_env(described_class::VECTOR_RAG_ENV_KEY, 'true') do
          stub_sections = [
            { content_chunk: 'Hybrid section.', citation: { file: 'docs/X.md', heading: 'Y', anchor: 'y', excerpt: 'ex' }, id: 'docs/X.md#y' }
          ]
          hybrid = instance_double(Ai::Rag::HybridRetriever, call: { sections: stub_sections, seed_ids: ['docs/X.md#y'] })
          allow(Ai::Rag::HybridRetriever).to receive(:new).and_return(hybrid)

          result = described_class.call('query')
          expect(result).to have_key(:context_text)
          expect(result).to have_key(:citations)
          expect(result[:context_text]).to include('Hybrid section.')
          expect(Ai::Rag::HybridRetriever).to have_received(:new).with('query', agent_key: nil)
        end
      end
    end

    it 'logs and returns GraphExpandedRetriever result (context_text + citations only) when enabled' do
      with_env(described_class::VECTOR_RAG_ENV_KEY, 'false') do
      with_env(described_class::ENV_KEY, 'true') do
        logged = nil
        allow(Rails.logger).to receive(:info) { |arg| logged = arg }
        result = described_class.call('refund')
        expect(result).to have_key(:context_text)
        expect(result).to have_key(:citations)
        expect(result.keys).to contain_exactly(:context_text, :citations, :context_truncated)
        parsed = JSON.parse(logged)
        expect(parsed['event']).to eq('ai_doc_retrieval')
        expect(parsed['retriever']).to eq('GraphExpandedRetriever')
        expect(parsed['seed_sections_count']).to be_a(Integer)
        expect(parsed['expanded_sections_count']).to be_a(Integer)
        expect(parsed['final_sections_count']).to be_a(Integer)
      end
      end
    end
  end

  describe 'smoke: both paths return valid shape' do
    before do
      Ai::Rag::DocsIndex.reset!
      Ai::Rag::ContextGraph.reset!
    end

    it 'keyword path (flag off) returns context_text and citations' do
      with_env(described_class::ENV_KEY, 'false') do
        result = described_class.call('authorize capture', agent_key: :operational)
        expect(result).to be_a(Hash)
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
    end

    it 'graph path (flag on) returns context_text and citations' do
      with_env(described_class::ENV_KEY, 'true') do
        result = described_class.call('authorize capture')
        expect(result).to be_a(Hash)
        expect(result).to have_key(:context_text)
        expect(result).to have_key(:citations)
        expect(result).to have_key(:context_truncated)
        expect(result[:citations]).to be_a(Array)
        result[:citations].each do |c|
          expect(c).to have_key(:file)
          expect(c).to have_key(:heading)
          expect(c).to have_key(:anchor)
          expect(c).to have_key(:excerpt)
        end
      end
    end
  end

  describe 'context budget' do
    before do
      Ai::Rag::DocsIndex.reset!
      Ai::Rag::ContextGraph.reset!
    end

    it 'with small budget still includes top seed section' do
      with_env(described_class::ENV_KEY, 'false') do
        # Use a tiny budget: only the first section should fit (and may be truncated)
        result = described_class.call('refund', agent_key: :operational, max_context_chars: 50)
        expect(result).to have_key(:context_text)
        expect(result).to have_key(:citations)
        expect(result[:context_text].to_s.length).to be <= 50
        # Top seed must still be included: at least one citation and non-empty context
        expect(result[:citations].size).to be >= 1
        expect(result[:context_text]).to be_present
      end
    end

    it 'citations match included sections only when budget truncates' do
      # Unit test: apply_context_budget returns citations only for included sections
      sections = [
        { content_chunk: 'aaa', citation: { file: 'a.md', heading: 'A', anchor: 'a', excerpt: 'a' }, id: 'a.md#a' },
        { content_chunk: 'bb', citation: { file: 'b.md', heading: 'B', anchor: 'b', excerpt: 'b' }, id: 'b.md#b' },
        { content_chunk: 'ccc', citation: { file: 'c.md', heading: 'C', anchor: 'c', excerpt: 'c' }, id: 'c.md#c' }
      ]
      seed_ids = %w[a.md#a b.md#b c.md#c]
      # Budget fits first section only (aaa = 3 chars); first is always included
      out = described_class.apply_context_budget(sections, seed_ids, 3)
      expect(out[:context_text]).to eq('aaa')
      expect(out[:citations].size).to eq(1)
      expect(out[:citations].first[:heading]).to eq('A')
      expect(out[:context_truncated]).to be true

      # Budget fits first two sections (3 + 2 + 2 separator = 7)
      out2 = described_class.apply_context_budget(sections, seed_ids, 7)
      expect(out2[:context_text]).to eq("aaa\n\nbb")
      expect(out2[:citations].size).to eq(2)
      expect(out2[:citations].map { |c| c[:heading] }).to eq(%w[A B])
    end
  end
end
