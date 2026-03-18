# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Config::FeatureFlags do
  def with_env(key, value)
    orig = ENV[key]
    ENV[key] = value
    yield
  ensure
    ENV[key] = orig
  end

  describe '.ai_debug_enabled?' do
    it 'returns true when AI_DEBUG=true' do
      with_env('AI_DEBUG', 'true') { expect(described_class.ai_debug_enabled?).to be true }
    end

    it 'returns true when AI_DEBUG=1' do
      with_env('AI_DEBUG', '1') { expect(described_class.ai_debug_enabled?).to be true }
    end

    it 'returns false when AI_DEBUG is unset or false' do
      with_env('AI_DEBUG', '') { expect(described_class.ai_debug_enabled?).to be false }
      with_env('AI_DEBUG', 'false') { expect(described_class.ai_debug_enabled?).to be false }
    end
  end

  describe '.ai_streaming_enabled?' do
    it 'returns true when AI_STREAMING_ENABLED=true' do
      with_env('AI_STREAMING_ENABLED', 'true') { expect(described_class.ai_streaming_enabled?).to be true }
    end

    it 'returns false by default' do
      with_env('AI_STREAMING_ENABLED', '') { expect(described_class.ai_streaming_enabled?).to be false }
    end
  end

  describe '.ai_graph_retrieval_enabled?' do
    it 'returns true when AI_CONTEXT_GRAPH_ENABLED=true' do
      with_env('AI_CONTEXT_GRAPH_ENABLED', 'true') { expect(described_class.ai_graph_retrieval_enabled?).to be true }
    end

    it 'returns false when unset' do
      with_env('AI_CONTEXT_GRAPH_ENABLED', '') { expect(described_class.ai_graph_retrieval_enabled?).to be false }
    end
  end

  describe '.ai_vector_retrieval_enabled?' do
    it 'returns true when AI_VECTOR_RAG_ENABLED=true' do
      with_env('AI_VECTOR_RAG_ENABLED', 'true') { expect(described_class.ai_vector_retrieval_enabled?).to be true }
    end
  end

  describe '.internal_tooling_available?' do
    it 'returns true in development' do
      allow(Rails.env).to receive(:development?).and_return(true)
      allow(Rails.env).to receive(:test?).and_return(false)
      expect(described_class.internal_tooling_available?).to be true
    end

    it 'returns true in test' do
      allow(Rails.env).to receive(:development?).and_return(false)
      allow(Rails.env).to receive(:test?).and_return(true)
      expect(described_class.internal_tooling_available?).to be true
    end

    it 'returns false in production when AI_INTERNAL_TOOLING_ALLOWED not set' do
      allow(Rails.env).to receive(:development?).and_return(false)
      allow(Rails.env).to receive(:test?).and_return(false)
      with_env('AI_INTERNAL_TOOLING_ALLOWED', '') { expect(described_class.internal_tooling_available?).to be false }
    end

    it 'returns true in production when AI_INTERNAL_TOOLING_ALLOWED=true' do
      allow(Rails.env).to receive(:development?).and_return(false)
      allow(Rails.env).to receive(:test?).and_return(false)
      with_env('AI_INTERNAL_TOOLING_ALLOWED', 'true') { expect(described_class.internal_tooling_available?).to be true }
    end
  end

  describe '.safe_summary' do
    it 'returns a hash with only safe keys (no secrets)' do
      summary = described_class.safe_summary
      expect(summary).to be_a(Hash)
      expect(summary).to include(:ai_enabled, :ai_debug_enabled, :ai_streaming_enabled, :ai_graph_retrieval_enabled, :ai_vector_retrieval_enabled, :internal_tooling_available)
      expect(summary.keys.map(&:to_s)).not_to include(/password|secret|api_key|prompt/)
    end

    it 'returns frozen hash' do
      expect(described_class.safe_summary).to be_frozen
    end
  end
end
