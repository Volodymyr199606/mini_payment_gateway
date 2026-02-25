# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Rag::MarkdownSectionExtractor do
  describe '.extract' do
    it 'splits content by headings' do
      content = <<~MD
        # Title
        Intro text.
        ## Section One
        Content one.
        ## Section Two
        Content two.
      MD
      sections = described_class.extract(content)
      expect(sections.size).to eq(3)
      expect(sections[0][:heading]).to eq('Title')
      expect(sections[1][:heading]).to eq('Section One')
      expect(sections[1][:level]).to eq(2)
      expect(sections[1][:content]).to include('Content one')
      expect(sections[2][:heading]).to eq('Section Two')
      expect(sections[2][:content]).to include('Content two')
    end

    it 'includes file_path when given' do
      sections = described_class.extract("## Foo\nbar", file_path: 'docs/foo.md')
      expect(sections[0][:file]).to eq('docs/foo.md')
    end

    it 'treats document without headings as one section' do
      content = "No headings here.\nJust text."
      sections = described_class.extract(content)
      expect(sections.size).to eq(1)
      expect(sections[0][:heading]).to eq('Document')
      expect(sections[0][:content]).to include('No headings')
    end

    it 'handles ### level' do
      content = <<~MD
        ## Big
        Text.
        ### Small
        More text.
      MD
      sections = described_class.extract(content)
      expect(sections.size).to eq(2)
      expect(sections[1][:heading]).to eq('Small')
      expect(sections[1][:level]).to eq(3)
    end
  end
end
