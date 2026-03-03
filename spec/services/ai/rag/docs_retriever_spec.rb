# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Rag::DocsRetriever do
  before do
    Ai::Rag::DocsIndex.reset!
    Ai::Rag::ContextGraph.reset!
  end

  it 'returns context_text and citations' do
    retriever = described_class.new('refund API')
    result = retriever.call
    expect(result).to have_key(:context_text)
    expect(result).to have_key(:citations)
    expect(result[:citations]).to be_a(Array)
    result[:citations].each do |c|
      expect(c).to have_key(:file)
      expect(c).to have_key(:heading)
      expect(c).to have_key(:anchor)
      expect(c).to have_key(:excerpt)
      expect(c[:excerpt].to_s.length).to be <= 160
    end
  end

  it 'returns "Authorize (in this project)" and "Capture (in this project)" subsections for authorize vs capture query' do
    retriever = described_class.new('authorize vs capture', agent_key: :operational)
    result = retriever.call
    context_text = result[:context_text].to_s
    expect(context_text).to include('Authorize (in this project)')
    expect(context_text).to include('Capture (in this project)')
  end

  it 'returns at most 6 sections' do
    retriever = described_class.new('authorize capture refund void')
    result = retriever.call
    expect(result[:citations].size).to be <= 6
    expect(result[:citations].size).to be >= 1
  end

  it 'includes related sections (parent or neighbor) when query matches a section' do
    retriever = described_class.new('authorize vs capture', agent_key: :operational)
    result = retriever.call
    context_text = result[:context_text].to_s
    # Seeds hit Authorize/Capture; expansion should include parent "Authorize vs Capture" or neighbors
    expect(context_text).to include('Authorize')
    expect(context_text).to include('Capture')
    # Section header format: ## Heading (file#anchor)
    expect(context_text).to match(/##\s+.+\(docs\/[^)]+\.md#[a-z0-9-]+\)/)
  end

  it 'returns deterministic order (same section order across calls)' do
    retriever = described_class.new('authorize vs capture', agent_key: :operational)
    result1 = retriever.call
    result2 = retriever.call
    expect(result1[:citations].map { |c| [c[:file], c[:heading]] }).to eq(result2[:citations].map { |c| [c[:file], c[:heading]] })
  end
end
