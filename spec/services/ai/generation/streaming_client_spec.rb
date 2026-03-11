# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Generation::StreamingClient do
  describe '#stream' do
    it 'returns error hash when API key is blank' do
      client = described_class.new(api_key: '')
      chunks = []
      result = client.stream(messages: []) { |c| chunks << c }
      expect(result[:error]).to eq('GROQ_API_KEY not set')
      expect(result[:content]).to eq('')
      expect(chunks).to be_empty
    end

    it 'yields chunks and returns full content when API succeeds' do
      client = described_class.new(api_key: 'test-key')
      body = "data: {\"choices\":[{\"delta\":{\"content\":\"Hi\"}}]}\ndata: {\"choices\":[{\"delta\":{\"content\":\" there\"}}]}\ndata: [DONE]\n"
      mock_response = double('response')
      allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(mock_response).to receive(:read_body) do |&block|
        block&.call(body) if block
      end

      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:request).and_yield(mock_response)

      chunks = []
      result = client.stream(messages: [{ role: 'user', content: 'Hi' }]) { |c| chunks << c }

      expect(chunks).to eq(['Hi', ' there'])
      expect(result[:content]).to eq('Hi there')
      expect(result[:error]).to be_nil
    end

    it 'returns error hash on API failure' do
      client = described_class.new(api_key: 'test-key')
      mock_response = double('response')
      allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
      allow(mock_response).to receive(:body).and_return('{"error":{"message":"Unauthorized"}}')
      allow(mock_response).to receive(:code).and_return('401')

      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:request).and_yield(mock_response)

      result = client.stream(messages: [{ role: 'user', content: 'Hi' }])
      expect(result[:error]).to include('401')
      expect(result[:content]).to eq('')
    end
  end
end
