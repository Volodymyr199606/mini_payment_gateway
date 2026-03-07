# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Rag::SmokeHybrid do
  describe '.pgvector_enabled?' do
    it 'returns true when vector extension is present' do
      allow(ActiveRecord::Base.connection).to receive(:select_one)
        .with("SELECT 1 AS one FROM pg_extension WHERE extname = 'vector'")
        .and_return({ 'one' => 1 })
      expect(described_class.pgvector_enabled?).to be true
    end

    it 'returns false when vector extension is missing' do
      allow(ActiveRecord::Base.connection).to receive(:select_one)
        .with("SELECT 1 AS one FROM pg_extension WHERE extname = 'vector'")
        .and_return(nil)
      expect(described_class.pgvector_enabled?).to be false
    end

    it 'returns false on error' do
      allow(ActiveRecord::Base.connection).to receive(:select_one).and_raise(StandardError)
      expect(described_class.pgvector_enabled?).to be false
    end
  end

  describe '.doc_section_embeddings_exists?' do
    it 'returns false when DocSectionEmbedding.table_exists? raises' do
      fake = Class.new do
        def self.table_exists?
          raise StandardError, 'connection error'
        end
      end
      stub_const('DocSectionEmbedding', fake)
      expect(described_class.doc_section_embeddings_exists?).to be false
    end

    it 'returns the value from DocSectionEmbedding.table_exists? when it does not raise' do
      fake = Class.new do
        def self.table_exists?
          false
        end
      end
      stub_const('DocSectionEmbedding', fake)
      expect(described_class.doc_section_embeddings_exists?).to be false
    end
  end

  describe '.deterministic_embedding_for' do
    it 'returns an array of DIMENSIONS floats' do
      vec = described_class.deterministic_embedding_for('docs/REFUNDS.md#endpoint')
      expect(vec).to be_a(Array)
      expect(vec.size).to eq(Ai::Rag::EmbeddingClient::DIMENSIONS)
      expect(vec.all? { |x| x.is_a?(Float) }).to be true
    end

    it 'is deterministic for the same seed' do
      a = described_class.deterministic_embedding_for('same_seed')
      b = described_class.deterministic_embedding_for('same_seed')
      expect(a).to eq(b)
    end

    it 'differs for different seeds' do
      a = described_class.deterministic_embedding_for('seed_a')
      b = described_class.deterministic_embedding_for('seed_b')
      expect(a).not_to eq(b)
    end
  end
end
