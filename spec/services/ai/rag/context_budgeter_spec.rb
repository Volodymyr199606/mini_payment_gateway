# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Rag::ContextBudgeter do
  def section(id:, content:, citation: {})
    { id: id, content_chunk: content, citation: citation }
  end

  describe '.call' do
    it 'returns empty result when sections is empty' do
      result = described_class.call([])
      expect(result[:context_text]).to be_nil
      expect(result[:citations]).to eq([])
      expect(result[:context_truncated]).to be(false)
      expect(result[:included_section_ids]).to eq([])
      expect(result[:dropped_section_ids_count]).to eq(0)
      expect(result[:final_context_chars]).to eq(0)
      expect(result[:final_sections_count]).to eq(0)
    end

    it 'always includes the top-ranked (first) section' do
      sections = [
        section(id: 'a', content: 'A' * 20_000, citation: { file: 'a.md' }),
        section(id: 'b', content: 'B', citation: { file: 'b.md' })
      ]
      result = described_class.call(sections, max_context_chars: 1000)
      expect(result[:included_section_ids]).to eq(['a'])
      expect(result[:context_text]).to include('A')
      expect(result[:citations].size).to eq(1)
      expect(result[:context_truncated]).to be(true)
      expect(result[:dropped_section_ids_count]).to eq(1)
    end

    it 'drops lowest-ranked sections when context budget is exceeded' do
      sections = [
        section(id: '1', content: 'One', citation: {}),
        section(id: '2', content: 'Two', citation: {}),
        section(id: '3', content: 'Three', citation: {}),
        section(id: '4', content: 'Four', citation: {}),
        section(id: '5', content: 'Five', citation: {})
      ]
      result = described_class.call(sections, max_context_chars: 20, max_sections: 6, max_citations: 8)
      expect(result[:included_section_ids]).to include('1')
      expect(result[:final_sections_count]).to be <= 6
      expect(result[:final_context_chars]).to be <= 20
      expect(result[:context_truncated]).to be(true)
      expect(result[:dropped_section_ids_count]).to be_positive
    end

    it 'does not partially truncate section bodies' do
      sections = [
        section(id: '1', content: 'Short.', citation: {}),
        section(id: '2', content: 'This is a long section that would be truncated if we did partial truncation.', citation: {})
      ]
      result = described_class.call(sections, max_context_chars: 15, max_sections: 6)
      expect(result[:context_text]).to eq('Short.')
      expect(result[:context_text]).not_to include('This is a long')
      expect(result[:citations].size).to eq(1)
    end

    it 'caps sections by max_sections and max_citations' do
      sections = 10.times.map do |i|
        section(id: "id-#{i}", content: "Content #{i}", citation: { file: "f#{i}.md" })
      end
      result = described_class.call(sections, max_context_chars: 50_000, max_sections: 3, max_citations: 2)
      expect(result[:final_sections_count]).to eq(2)
      expect(result[:citations].size).to eq(2)
      expect(result[:included_section_ids]).to eq(%w[id-0 id-1])
      expect(result[:dropped_section_ids_count]).to eq(8)
    end

    it 'returns citations that align with included sections only' do
      sections = [
        section(id: '1', content: 'A', citation: { file: 'a.md', heading: 'A' }),
        section(id: '2', content: 'B', citation: { file: 'b.md', heading: 'B' }),
        section(id: '3', content: 'C', citation: { file: 'c.md', heading: 'C' })
      ]
      result = described_class.call(sections, max_context_chars: 10, max_sections: 2)
      expect(result[:citations].size).to eq(result[:final_sections_count])
      expect(result[:citations].map { |c| c[:file] }).to eq(%w[a.md b.md])
    end

    it 'sets metadata flags correctly' do
      sections = [
        section(id: '1', content: 'One', citation: {}),
        section(id: '2', content: 'Two', citation: {})
      ]
      result = described_class.call(sections, max_context_chars: 500)
      expect(result[:context_truncated]).to be(false)
      expect(result[:final_context_chars]).to eq(8) # "One\n\nTwo"
      expect(result[:final_sections_count]).to eq(2)
      expect(result[:dropped_section_ids_count]).to eq(0)
    end
  end
end
