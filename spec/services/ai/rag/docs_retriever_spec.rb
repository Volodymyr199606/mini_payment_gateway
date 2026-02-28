# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Rag::DocsRetriever do
  before { Ai::Rag::DocsIndex.reset! }

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
end
