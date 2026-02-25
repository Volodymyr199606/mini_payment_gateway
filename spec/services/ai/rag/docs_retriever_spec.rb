# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Rag::DocsRetriever do
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
end
