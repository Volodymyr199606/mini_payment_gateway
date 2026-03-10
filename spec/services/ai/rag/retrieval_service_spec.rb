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
        with_env(described_class::VECTOR_RAG_ENV_KEY, 'false') do
          logged = nil
          allow(Rails.logger).to receive(:info) { |arg| logged = arg }
          result = described_class.call('refund', agent_key: :operational)
          expect(result).to have_key(:context_text)
          expect(result).to have_key(:citations)
          expect(result[:citations]).to be_a(Array)
          parsed = JSON.parse(logged)
          expect(parsed['event']).to eq('ai_retrieval')
          expect(parsed['retriever']).to eq('DocsRetriever')
          expect(parsed['final_sections_count']).to be_a(Integer)
        end
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

    it 'logs and returns GraphExpandedRetriever result (context_text + citations + budget metadata) when enabled' do
      with_env(described_class::VECTOR_RAG_ENV_KEY, 'false') do
      with_env(described_class::ENV_KEY, 'true') do
        logged = nil
        allow(Rails.logger).to receive(:info) { |arg| logged = arg }
        result = described_class.call('refund')
        expect(result).to have_key(:context_text)
        expect(result).to have_key(:citations)
        expect(result).to have_key(:context_truncated)
        expect(result).to have_key(:final_context_chars)
        expect(result).to have_key(:final_sections_count)
        parsed = JSON.parse(logged)
        expect(parsed['event']).to eq('ai_retrieval')
        expect(parsed['retriever']).to eq('GraphExpandedRetriever')
        expect(parsed['seed_sections_count']).to be_a(Integer)
        expect(parsed['expanded_sections_count']).to be_a(Integer)
        expect(parsed['final_sections_count']).to be_a(Integer)
      end
      end
    end

    it 'calls GraphExpandedRetriever with agent_key when graph enabled' do
      with_env(described_class::VECTOR_RAG_ENV_KEY, 'false') do
        with_env(described_class::ENV_KEY, 'true') do
          stub_sections = [
            { content_chunk: 'Graph section.', citation: { file: 'docs/X.md', heading: 'Y', anchor: 'y', excerpt: 'ex' }, id: 'docs/X.md#y' }
          ]
          graph_retriever = instance_double(Ai::GraphExpandedRetriever, call: { sections: stub_sections, seed_ids: ['docs/X.md#y'], seed_count: 1, expanded_count: 0 })
          allow(Ai::GraphExpandedRetriever).to receive(:new).and_return(graph_retriever)

          described_class.call('authorize capture', agent_key: :operational)

          expect(Ai::GraphExpandedRetriever).to have_received(:new).with('authorize capture', agent_key: :operational)
        end
      end
    end

    it 'AgentDocPolicy sees agent_key when graph path is used' do
      with_env(described_class::VECTOR_RAG_ENV_KEY, 'false') do
        with_env(described_class::ENV_KEY, 'true') do
          allow(Ai::Rag::AgentDocPolicy).to receive(:for_agent).and_call_original

          described_class.call('authorize capture', agent_key: :operational)

          expect(Ai::Rag::AgentDocPolicy).to have_received(:for_agent).with(:operational)
        end
      end
    end

    describe 'feature flag selection' do
      let(:stub_sections) do
        [{ content_chunk: 'Stub.', citation: { file: 'docs/X.md', heading: 'Y', anchor: 'y', excerpt: 'ex' }, id: 'docs/X.md#y' }]
      end

      it 'uses GraphExpandedRetriever when AI_CONTEXT_GRAPH_ENABLED is true (graph over vector)' do
        with_env(described_class::ENV_KEY, 'true') do
          with_env(described_class::VECTOR_RAG_ENV_KEY, 'true') do
            graph_ret = instance_double(Ai::GraphExpandedRetriever, call: { sections: stub_sections, seed_ids: ['docs/X.md#y'], seed_count: 1, expanded_count: 0 })
            allow(Ai::GraphExpandedRetriever).to receive(:new).and_return(graph_ret)
            allow(Ai::Rag::HybridRetriever).to receive(:new)

            described_class.call('query', agent_key: :operational)

            expect(Ai::GraphExpandedRetriever).to have_received(:new).with('query', agent_key: :operational)
            expect(Ai::Rag::HybridRetriever).not_to have_received(:new)
          end
        end
      end

      it 'uses HybridRetriever when AI_VECTOR_RAG_ENABLED is true and graph is false' do
        with_env(described_class::ENV_KEY, 'false') do
          with_env(described_class::VECTOR_RAG_ENV_KEY, 'true') do
            hybrid = instance_double(Ai::Rag::HybridRetriever, call: { sections: stub_sections, seed_ids: ['docs/X.md#y'] })
            allow(Ai::Rag::HybridRetriever).to receive(:new).and_return(hybrid)

            described_class.call('query', agent_key: :support_faq)

            expect(Ai::Rag::HybridRetriever).to have_received(:new).with('query', agent_key: :support_faq)
          end
        end
      end

      it 'uses DocsRetriever when both flags are false' do
        with_env(described_class::ENV_KEY, 'false') do
          with_env(described_class::VECTOR_RAG_ENV_KEY, 'false') do
            docs_ret = instance_double(Ai::Rag::DocsRetriever, call: { sections: stub_sections, seed_ids: ['docs/X.md#y'] })
            allow(Ai::Rag::DocsRetriever).to receive(:new).and_return(docs_ret)

            described_class.call('query', agent_key: :operational)

            expect(Ai::Rag::DocsRetriever).to have_received(:new).with('query', agent_key: :operational)
          end
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

    it 'with small budget still includes top seed section (whole section, no partial truncation)' do
      with_env(described_class::ENV_KEY, 'false') do
        # Top-ranked section is always included whole; others dropped when over budget
        result = described_class.call('refund', agent_key: :operational, max_context_chars: 50)
        expect(result).to have_key(:context_text)
        expect(result).to have_key(:citations)
        expect(result).to have_key(:final_context_chars)
        expect(result[:citations].size).to be >= 1
        expect(result[:context_text]).to be_present
        expect(result[:final_sections_count]).to eq(result[:citations].size)
      end
    end

    it 'citations match included sections only when budget truncates' do
      sections = [
        { content_chunk: 'aaa', citation: { file: 'a.md', heading: 'A', anchor: 'a', excerpt: 'a' }, id: 'a.md#a' },
        { content_chunk: 'bb', citation: { file: 'b.md', heading: 'B', anchor: 'b', excerpt: 'b' }, id: 'b.md#b' },
        { content_chunk: 'ccc', citation: { file: 'c.md', heading: 'C', anchor: 'c', excerpt: 'c' }, id: 'c.md#c' }
      ]
      out = Ai::Rag::ContextBudgeter.call(sections, max_context_chars: 3)
      expect(out[:context_text]).to eq('aaa')
      expect(out[:citations].size).to eq(1)
      expect(out[:citations].first[:heading]).to eq('A')
      expect(out[:context_truncated]).to be true

      out2 = Ai::Rag::ContextBudgeter.call(sections, max_context_chars: 7)
      expect(out2[:context_text]).to eq("aaa\n\nbb")
      expect(out2[:citations].size).to eq(2)
      expect(out2[:citations].map { |c| c[:heading] }).to eq(%w[A B])
    end
  end
end
