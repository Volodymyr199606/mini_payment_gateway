# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Rag::Helpers do
  describe '.normalize_file' do
    it 'replaces backslashes with forward slashes' do
      expect(described_class.normalize_file('docs\\REFUNDS.md')).to eq('docs/REFUNDS.md')
    end

    it 'leaves forward slashes unchanged' do
      expect(described_class.normalize_file('docs/REFUNDS.md')).to eq('docs/REFUNDS.md')
    end

    it 'converts non-string to string' do
      expect(described_class.normalize_file(nil)).to eq('')
    end
  end

  describe '.slugify_heading' do
    it 'lowercases and replaces non-alphanumeric with single hyphen' do
      expect(described_class.slugify_heading('Authorize in this project')).to eq('authorize-in-this-project')
    end

    it 'strips leading and trailing hyphens' do
      expect(described_class.slugify_heading('  Spaces  ')).to eq('spaces')
    end

    it 'handles empty string' do
      expect(described_class.slugify_heading('')).to eq('')
    end

    it 'handles nil' do
      expect(described_class.slugify_heading(nil)).to eq('')
    end
  end

  describe '.section_id' do
    it 'returns file#anchor format' do
      expect(described_class.section_id('docs/REFUNDS.md', 'endpoint')).to eq('docs/REFUNDS.md#endpoint')
    end
  end

  describe '.build_citation' do
    it 'returns file, heading, anchor, excerpt with excerpt truncated to EXCERPT_LENGTH' do
      section = {
        file: 'docs/REFUNDS.md',
        heading: 'Endpoint',
        content: 'A' * 200
      }
      citation = described_class.build_citation(section)
      expect(citation[:file]).to eq('docs/REFUNDS.md')
      expect(citation[:heading]).to eq('Endpoint')
      expect(citation[:anchor]).to eq('endpoint')
      expect(citation[:excerpt].length).to eq(160)
      expect(citation[:excerpt]).to end_with('...')
    end

    it 'normalizes file path' do
      section = { file: 'docs\\REFUNDS.md', heading: 'Foo', content: 'x' }
      citation = described_class.build_citation(section)
      expect(citation[:file]).to eq('docs/REFUNDS.md')
    end

    it 'uses provided anchor when present' do
      section = { file: 'docs/X.md', heading: 'Custom Heading', anchor: 'custom-anchor', content: 'y' }
      citation = described_class.build_citation(section)
      expect(citation[:anchor]).to eq('custom-anchor')
    end

    it 'computes anchor from heading when anchor not provided' do
      section = { file: 'docs/X.md', heading: 'How to Refund', content: 'z' }
      citation = described_class.build_citation(section)
      expect(citation[:anchor]).to eq('how-to-refund')
    end
  end
end
