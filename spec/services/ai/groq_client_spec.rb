# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::GroqClient do
  let(:api_key) { 'test-key' }

  describe 'default model' do
    it 'uses llama-3.3-70b-versatile when GROQ_MODEL is not set' do
      allow(ENV).to receive(:fetch).with('GROQ_API_KEY', nil).and_return(api_key)
      allow(ENV).to receive(:fetch).with('GROQ_BASE_URL', anything).and_return('https://api.groq.com/openai/v1')
      allow(ENV).to receive(:fetch).with('GROQ_MODEL', nil).and_return(nil)
      client = described_class.new(api_key: api_key)
      expect(client.instance_variable_get(:@model)).to eq('llama-3.3-70b-versatile')
    end

    it 'uses GROQ_MODEL when set' do
      allow(ENV).to receive(:fetch).with('GROQ_API_KEY', nil).and_return(nil)
      allow(ENV).to receive(:fetch).with('GROQ_BASE_URL', anything).and_return('https://api.groq.com/openai/v1')
      allow(ENV).to receive(:fetch).with('GROQ_MODEL', nil).and_return('custom-model')
      client = described_class.new(api_key: api_key)
      expect(client.instance_variable_get(:@model)).to eq('custom-model')
    end
  end

  describe '#chat' do
    def success_response(content)
      double(success?: true, body: { 'choices' => [{ 'message' => { 'content' => content } }] }, status: 200)
    end

    def error_response(code:, message:)
      double(
        success?: false,
        body: { 'error' => { 'code' => code, 'message' => message } },
        status: 400
      )
    end

    it 'returns content and model_used on success' do
      conn = instance_double(Faraday::Connection, post: success_response('Hello'))
      allow(Faraday).to receive(:new).and_return(conn)
      client = described_class.new(api_key: api_key)
      result = client.chat(messages: [{ role: 'user', content: 'Hi' }])
      expect(result[:content]).to eq('Hello')
      expect(result[:model_used]).to eq('llama-3.3-70b-versatile')
      expect(result[:fallback_used]).to eq(false)
    end

    it 'retries with fallback model when response indicates model_decommissioned' do
      decommissioned = error_response(code: 'model_decommissioned', message: 'Model is decommissioned')
      fallback_ok = success_response('Fallback reply')
      conn = instance_double(Faraday::Connection)
      allow(conn).to receive(:post).and_return(decommissioned, fallback_ok)
      allow(Faraday).to receive(:new).and_return(conn)
      client = described_class.new(api_key: api_key)
      result = client.chat(messages: [{ role: 'user', content: 'Hi' }])
      expect(result[:content]).to eq('Fallback reply')
      expect(result[:model_used]).to eq('llama-3.1-8b-instant')
      expect(result[:fallback_used]).to eq(true)
      expect(conn).to have_received(:post).twice
    end

    it 'retries when error message contains decommissioned' do
      decommissioned_msg = error_response(code: 'invalid_request', message: 'This model has been decommissioned.')
      fallback_ok = success_response('OK')
      conn = instance_double(Faraday::Connection)
      allow(conn).to receive(:post).and_return(decommissioned_msg, fallback_ok)
      allow(Faraday).to receive(:new).and_return(conn)
      client = described_class.new(api_key: api_key)
      result = client.chat(messages: [{ role: 'user', content: 'Hi' }])
      expect(result[:content]).to eq('OK')
      expect(result[:fallback_used]).to eq(true)
    end
  end
end
