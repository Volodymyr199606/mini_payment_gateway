# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Config::RuntimeConfig do
  def with_env(key, value)
    orig = ENV[key]
    ENV[key] = value
    yield
  ensure
    ENV[key] = orig
  end

  describe '.max_memory_chars' do
    it 'returns ENV value when set' do
      with_env('AI_MAX_MEMORY_CHARS', '8000') { expect(described_class.max_memory_chars).to eq(8000) }
    end

    it 'returns default when unset' do
      with_env('AI_MAX_MEMORY_CHARS', '') { expect(described_class.max_memory_chars).to eq(4000) }
    end
  end

  describe '.max_context_chars' do
    it 'returns ENV value when set' do
      with_env('AI_MAX_CONTEXT_CHARS', '16000') { expect(described_class.max_context_chars).to eq(16000) }
    end

    it 'returns default when unset' do
      with_env('AI_MAX_CONTEXT_CHARS', '') { expect(described_class.max_context_chars).to eq(12_000) }
    end
  end

  describe '.cache_doc_version' do
    it 'returns ENV value when set' do
      with_env('AI_CACHE_DOC_VERSION', 'v2') { expect(described_class.cache_doc_version).to eq('v2') }
    end

    it 'returns default when unset' do
      with_env('AI_CACHE_DOC_VERSION', '') { expect(described_class.cache_doc_version).to eq('v1') }
    end
  end
end
