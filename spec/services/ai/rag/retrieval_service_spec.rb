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

    it 'logs and returns GraphExpandedRetriever result (context_text + citations only) when enabled' do
      with_env(described_class::ENV_KEY, 'true') do
        logged = nil
        allow(Rails.logger).to receive(:info) { |arg| logged = arg }
        result = described_class.call('refund')
        expect(result).to have_key(:context_text)
        expect(result).to have_key(:citations)
        expect(result.keys).to contain_exactly(:context_text, :citations)
        parsed = JSON.parse(logged)
        expect(parsed['event']).to eq('ai_doc_retrieval')
        expect(parsed['retriever']).to eq('GraphExpandedRetriever')
        expect(parsed['seed_sections_count']).to be_a(Integer)
        expect(parsed['expanded_sections_count']).to be_a(Integer)
        expect(parsed['final_sections_count']).to be_a(Integer)
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
end
