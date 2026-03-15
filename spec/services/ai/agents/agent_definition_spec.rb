# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Agents::AgentDefinition do
  describe 'initialization and accessors' do
    let(:defn) do
      described_class.new(
        key: :test_agent,
        class_name: 'Ai::Agents::TestAgent',
        description: 'Test agent',
        supports_retrieval: true,
        supports_memory: false,
        debug_label: 'Test'
      )
    end

    it 'exposes key and class_name' do
      expect(defn.key).to eq(:test_agent)
      expect(defn.class_name).to eq('Ai::Agents::TestAgent')
    end

    it 'exposes capability flags' do
      expect(defn.supports_retrieval?).to be true
      expect(defn.supports_memory?).to be false
    end

    it 'returns debug_label' do
      expect(defn.debug_label).to eq('Test')
    end

    it 'defaults debug_label to key when not provided' do
      d = described_class.new(key: :foo, class_name: 'Foo')
      expect(d.debug_label).to eq('foo')
    end

    it 'returns to_h with expected keys' do
      h = defn.to_h
      expect(h).to include(:key, :class_name, :description, :supports_retrieval, :supports_memory, :debug_label)
    end
  end
end
