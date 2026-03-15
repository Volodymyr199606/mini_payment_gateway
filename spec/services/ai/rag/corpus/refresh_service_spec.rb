# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Rag::Corpus::RefreshService do
  describe '.call' do
    it 'resets DocsIndex and ContextGraph and returns current state' do
      expect(Ai::Rag::DocsIndex).to receive(:reset!)
      expect(Ai::Rag::ContextGraph).to receive(:reset!)
      expect(Ai::Rag::Corpus::StateService).to receive(:call).and_return(
        Ai::Rag::Corpus::State.new(corpus_version: 'x', docs_count: 5, last_changed_at: Time.current, graph_enabled: false, vector_enabled: false, last_indexed_at: Time.current, stale: false)
      )

      state = described_class.call
      expect(state.corpus_version).to eq('x')
    end
  end
end
