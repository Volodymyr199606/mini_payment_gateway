# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Streaming::ResponseStreamer do
  describe '#<<' do
    it 'accumulates chunks into full_content' do
      streamer = described_class.new
      streamer << 'Hello'
      streamer << ' '
      streamer << 'world'
      expect(streamer.full_content).to eq('Hello world')
    end

    it 'yields to block when given' do
      streamer = described_class.new
      received = []
      streamer.send(:<<, 'a') { |c| received << c }
      streamer.send(:<<, 'b') { |c| received << c }
      expect(received).to eq(%w[a b])
      expect(streamer.full_content).to eq('ab')
    end
  end

  describe '#append_all' do
    it 'appends bulk content' do
      streamer = described_class.new
      streamer.append_all('Full reply here')
      expect(streamer.full_content).to eq('Full reply here')
    end
  end
end
