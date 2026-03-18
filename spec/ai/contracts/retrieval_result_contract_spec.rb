# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'RetrievalResult contract' do
  describe 'to_h shape' do
    it 'includes stable context and citation keys and contract_version' do
      result = Ai::Contracts::RetrievalResult.new(
        context_text: 'Doc content',
        citations: [{ file: 'docs/A.md', section: '1' }],
        context_truncated: false,
        final_sections_count: 2,
        contract_version: nil
      )
      h = result.to_h
      expect(h).to have_key(:context_text)
      expect(h).to have_key(:citations)
      expect(h[:citations]).to be_a(Array)
      expect(h).to have_key(:context_truncated)
      expect(h).to have_key(:contract_version)
      expect(h[:contract_version]).to eq(Ai::Contracts::RETRIEVAL_RESULT_VERSION)
    end

    it 'from_h round-trips' do
      original = { context_text: 'x', citations: [], context_truncated: true, contract_version: '1' }
      obj = Ai::Contracts::RetrievalResult.from_h(original)
      expect(obj).to be_present
      expect(obj.to_h[:contract_version]).to be_present
    end

    it 'does not expose sensitive fields' do
      result = Ai::Contracts::RetrievalResult.new(context_text: 'safe', citations: [])
      AiContractHelpers.assert_no_forbidden_keys!(result.to_h, contract_name: 'RetrievalResult')
    end
  end
end
