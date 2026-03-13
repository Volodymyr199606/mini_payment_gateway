# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Performance::CacheFetcher do
  around do |ex|
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache.lookup_store(:memory_store)
    ex.run
  ensure
    Rails.cache = original
  end

  before do
    allow(Ai::Performance::CachePolicy).to receive(:bypass?).and_return(false)
    allow(Ai::Observability::EventLogger).to receive(:log_cache)
  end

  describe '.fetch' do
    it 'computes and caches on miss' do
      key = 'ai:test:spec:1'
      result = described_class.fetch(key: key, category: :retrieval) { { context_text: 'cached' } }
      expect(result[:context_text]).to eq('cached')
      expect(Rails.cache.read(key)).to be_present
    end

    it 'returns cached value on hit' do
      key = 'ai:test:spec:2'
      Rails.cache.write(key, { 'context_text' => 'from_cache' }, expires_in: 60)
      result = described_class.fetch(key: key, category: :retrieval) { raise 'should not run' }
      expect(result[:context_text]).to eq('from_cache')
    end

    it 'bypasses cache when policy says bypass' do
      allow(Ai::Performance::CachePolicy).to receive(:bypass?).and_return(true)
      key = 'ai:test:spec:3'
      count = 0
      result = described_class.fetch(key: key, category: :retrieval, bypass: true) { count += 1; { x: count } }
      expect(result[:x]).to eq(1)
      # Second call with bypass should still compute (no cache read)
      result2 = described_class.fetch(key: key, category: :retrieval, bypass: true) { count += 1; { x: count } }
      expect(result2[:x]).to eq(2)
    end

    it 'does not cache failure results' do
      key = 'ai:test:spec:4'
      described_class.fetch(key: key, category: :tool_other) { { success: false, error: 'fail' } }
      expect(Rails.cache.read(key)).to be_nil
    end

    it 'logs cache events' do
      key = 'ai:test:spec:5'
      described_class.fetch(key: key, category: :retrieval) { { a: 1 } }
      expect(Ai::Observability::EventLogger).to have_received(:log_cache).with(
        hash_including(cache_category: :retrieval, cache_outcome: :miss)
      )
    end
  end
end
