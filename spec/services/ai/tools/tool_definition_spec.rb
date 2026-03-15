# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Tools::ToolDefinition do
  describe 'initialization and accessors' do
    let(:defn) do
      described_class.new(
        key: 'get_test',
        class_name: 'Ai::Tools::GetTest',
        description: 'Test tool',
        read_only: true,
        cacheable: true
      )
    end

    it 'exposes key and class_name' do
      expect(defn.key).to eq('get_test')
      expect(defn.class_name).to eq('Ai::Tools::GetTest')
    end

    it 'exposes read_only and cacheable' do
      expect(defn.read_only?).to be true
      expect(defn.cacheable?).to be true
    end

    it 'returns to_h with expected keys' do
      h = defn.to_h
      expect(h).to include(:key, :class_name, :description, :read_only, :cacheable)
    end
  end
end
