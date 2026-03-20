# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RateLimiterService do
  around do |example|
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache.lookup_store(:memory_store)
    example.run
    Rails.cache = original
  end

  describe '#call' do
    it 'allows requests under the limit and exposes remaining' do
      svc = described_class.call(cache_key_prefix: 'spec:rl:a', limit: 3, window_seconds: 3600)
      expect(svc.result[:limited]).to be false
      expect(svc.result[:remaining]).to eq(2)

      svc2 = described_class.call(cache_key_prefix: 'spec:rl:a', limit: 3, window_seconds: 3600)
      expect(svc2.result[:remaining]).to eq(1)
    end

    it 'blocks when limit is reached' do
      prefix = 'spec:rl:b'
      2.times { described_class.call(cache_key_prefix: prefix, limit: 2, window_seconds: 3600) }

      svc = described_class.call(cache_key_prefix: prefix, limit: 2, window_seconds: 3600)
      expect(svc.result[:limited]).to be true
      expect(svc.result[:remaining]).to eq(0)
      expect(svc.result[:retry_after_seconds]).to be_between(1, 3600)
    end
  end
end
