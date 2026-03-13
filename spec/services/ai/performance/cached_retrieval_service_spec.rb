# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Performance::CachedRetrievalService do
  let(:retrieval_result) do
    {
      context_text: 'Doc content',
      citations: [{ file: 'docs/X.md', heading: 'Y' }],
      context_truncated: false,
      final_context_chars: 100,
      final_sections_count: 1,
      dropped_section_ids_count: 0,
      included_section_ids: ['docs/X#y']
    }
  end

  around do |ex|
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache.lookup_store(:memory_store)
    ex.run
  ensure
    Rails.cache = original
  end

  before do
    allow(Ai::Rag::RetrievalService).to receive(:call).and_return(retrieval_result)
    allow(Ai::Rag::RetrievalService).to receive(:context_graph_enabled?).and_return(false)
    allow(Ai::Rag::RetrievalService).to receive(:vector_rag_enabled?).and_return(false)
    allow(Ai::Performance::CachePolicy).to receive(:bypass?).and_return(false)
  end

  it 'returns retrieval result' do
    result = described_class.call('how do refunds work?', agent_key: :support_faq)
    expect(result[:context_text]).to eq('Doc content')
    expect(result[:citations].size).to eq(1)
  end

  it 'calls RetrievalService on first request' do
    described_class.call('test query', agent_key: :support_faq)
    expect(Ai::Rag::RetrievalService).to have_received(:call).once
  end

  it 'returns cached result on second request with same query' do
    described_class.call('same query', agent_key: :support_faq)
    described_class.call('same query', agent_key: :support_faq)
    expect(Ai::Rag::RetrievalService).to have_received(:call).once
  end

  it 'calls RetrievalService again when bypass is set' do
    allow(Ai::Performance::CachePolicy).to receive(:bypass?).and_return(true)
    r1 = described_class.call('query A', agent_key: :support_faq)
    r2 = described_class.call('query A', agent_key: :support_faq)
    expect(r1[:context_text]).to eq('Doc content')
    expect(r2[:context_text]).to eq('Doc content')
    expect(Ai::Rag::RetrievalService).to have_received(:call).at_least(:twice)
  end

  it 'uses different cache keys for different agents' do
    described_class.call('refunds', agent_key: :support_faq)
    described_class.call('refunds', agent_key: :operational)
    expect(Ai::Rag::RetrievalService).to have_received(:call).twice
  end
end
