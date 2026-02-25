# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Rag::DocsIndex do
  before { Ai::Rag::DocsIndex.reset! }

  describe '#search' do
    it 'returns empty when query is too short' do
      index = Ai::Rag::DocsIndex.new.build
      expect(index.search('a', top_k: 5)).to eq([])
    end

    it 'returns sections matching query terms' do
      index = Ai::Rag::DocsIndex.new.build
      results = index.search('refund payment', top_k: 5)
      expect(results).to be_a(Array)
      results.each do |s|
        expect(s).to have_key(:file)
        expect(s).to have_key(:heading)
        expect(s).to have_key(:content)
      end
    end

    it 'limits results to top_k' do
      index = Ai::Rag::DocsIndex.new.build
      results = index.search('api endpoint', top_k: 2)
      expect(results.size).to be <= 2
    end
  end

  describe '#sections' do
    it 'builds sections from docs folder' do
      index = Ai::Rag::DocsIndex.new.build
      expect(index.sections).to be_a(Array)
      index.sections.each do |s|
        expect(s).to include(:file, :heading, :level, :content, :keywords)
      end
    end
  end
end
