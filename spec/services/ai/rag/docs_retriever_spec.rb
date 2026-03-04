# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Rag::DocsRetriever do
  before do
    Ai::Rag::DocsIndex.reset!
    Ai::Rag::ContextGraph.reset!
  end

  # Docs path is exercised via RetrievalService (graph off); retriever returns sections + seed_ids
  it 'returns sections and seed_ids' do
    retriever = described_class.new('refund API')
    result = retriever.call
    expect(result).to have_key(:sections)
    expect(result).to have_key(:seed_ids)
    expect(result[:sections]).to be_a(Array)
    result[:sections].each do |s|
      expect(s).to have_key(:content_chunk)
      expect(s).to have_key(:citation)
      expect(s).to have_key(:id)
      c = s[:citation]
      expect(c[:excerpt].to_s.length).to be <= 160 if c
    end
  end

  it 'returns "Authorize (in this project)" and "Capture (in this project)" subsections for authorize vs capture query' do
    ENV[Ai::Rag::RetrievalService::ENV_KEY] = 'false'
    result = Ai::Rag::RetrievalService.call('authorize vs capture', agent_key: :operational)
    context_text = result[:context_text].to_s
    expect(context_text).to include('Authorize (in this project)')
    expect(context_text).to include('Capture (in this project)')
  ensure
    ENV.delete(Ai::Rag::RetrievalService::ENV_KEY)
  end

  it 'returns at most 6 sections (via service budget)' do
    ENV[Ai::Rag::RetrievalService::ENV_KEY] = 'false'
    result = Ai::Rag::RetrievalService.call('authorize capture refund void', agent_key: :operational)
    expect(result[:citations].size).to be <= 6
    expect(result[:citations].size).to be >= 1
  ensure
    ENV.delete(Ai::Rag::RetrievalService::ENV_KEY)
  end

  it 'includes related sections (parent or neighbor) when query matches a section' do
    ENV[Ai::Rag::RetrievalService::ENV_KEY] = 'false'
    result = Ai::Rag::RetrievalService.call('authorize vs capture', agent_key: :operational)
    context_text = result[:context_text].to_s
    expect(context_text).to include('Authorize')
    expect(context_text).to include('Capture')
    expect(context_text).to match(/##\s+.+\(docs\/[^)]+\.md#[a-z0-9-]+\)/)
  ensure
    ENV.delete(Ai::Rag::RetrievalService::ENV_KEY)
  end

  it 'returns deterministic order (same section order across calls)' do
    ENV[Ai::Rag::RetrievalService::ENV_KEY] = 'false'
    result1 = Ai::Rag::RetrievalService.call('authorize vs capture', agent_key: :operational)
    result2 = Ai::Rag::RetrievalService.call('authorize vs capture', agent_key: :operational)
    expect(result1[:citations].map { |c| [c[:file], c[:heading]] }).to eq(result2[:citations].map { |c| [c[:file], c[:heading]] })
  ensure
    ENV.delete(Ai::Rag::RetrievalService::ENV_KEY)
  end
end
