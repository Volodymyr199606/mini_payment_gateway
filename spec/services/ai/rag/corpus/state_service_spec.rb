# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Rag::Corpus::StateService do
  describe '.call' do
    it 'returns a State with corpus_version and docs_count' do
      state = described_class.call
      expect(state).to be_a(Ai::Rag::Corpus::State)
      expect(state.corpus_version).to be_present
      expect(state.docs_count).to be_a(Integer)
      expect(state.docs_count).to be >= 0
    end

    it 'includes graph_enabled and vector_enabled from ENV' do
      state = described_class.call
      expect([true, false]).to include(state.graph_enabled)
      expect([true, false]).to include(state.vector_enabled)
    end

    it 'to_h is serializable' do
      state = described_class.call
      h = state.to_h
      expect(h).to have_key(:corpus_version)
      expect(h).to have_key(:docs_count)
      expect(h).to have_key(:last_changed_at)
    end
  end
end
