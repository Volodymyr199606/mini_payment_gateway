# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Dev AI Playground', type: :request do
  # Dev routes are only available in development/test via DevRoutesConstraint
  def csrf_token
    get dev_ai_playground_path
    response.body[/name="csrf-token" content="([^"]+)"/, 1] ||
      response.body[/name="authenticity_token" value="([^"]+)"/, 1]
  end

  def stub_retrieval!
    allow(Ai::Rag::RetrievalService).to receive(:call).and_return(
      context_text: 'Stubbed context for playground test.',
      citations: [{ file: 'docs/X.md', heading: 'Test', excerpt: 'Excerpt.' }],
      final_sections_count: 1,
      context_truncated: false,
      debug: { retriever: 'DocsRetriever' }
    )
  end

  def stub_groq!
    allow(Ai::GroqClient).to receive(:new).and_return(
      instance_double(Ai::GroqClient, chat: { content: 'Stubbed reply.', model_used: 'test', fallback_used: false })
    )
  end

  describe 'GET /dev/ai_playground' do
    it 'returns 200 in test environment' do
      get dev_ai_playground_path
      expect(response).to have_http_status(:ok)
    end

    it 'renders the playground form with presets' do
      get dev_ai_playground_path
      expect(response.body).to include('AI Playground')
      expect(response.body).to include('Message')
      expect(response.body).to include('Run')
      expect(response.body).to include('How do refunds work?')
    end

    it 'returns 404 when not in development or test' do
      allow(Rails.env).to receive(:development?).and_return(false)
      allow(Rails.env).to receive(:test?).and_return(false)

      get dev_ai_playground_path
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /dev/ai_playground/run' do
    it 'returns 400 for blank message' do
      merchant, _key = create_merchant_with_api_key
      post dev_ai_playground_run_path,
           params: { message: '', merchant_id: merchant.id },
           headers: { 'Accept' => 'application/json' },
           as: :json
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body['error']).to eq('Message is required')
    end

    it 'returns 400 when no merchant exists' do
      Merchant.destroy_all
      post dev_ai_playground_run_path,
           params: { message: 'Hello', merchant_id: nil },
           headers: { 'Accept' => 'application/json', 'X-CSRF-Token' => csrf_token },
           as: :json
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body['error']).to include('merchant')
    end

    it 'returns structured results with expected sections' do
      merchant, _key = create_merchant_with_api_key
      stub_retrieval!
      stub_groq!

      post dev_ai_playground_run_path,
           params: { message: 'What is a refund?', merchant_id: merchant.id },
           headers: { 'Accept' => 'application/json', 'X-CSRF-Token' => csrf_token },
           as: :json

      expect(response).to have_http_status(:ok), -> { "Body: #{response.parsed_body.inspect}" }
      body = response.parsed_body
      expect(body).to have_key('input')
      expect(body).to have_key('parsing')
      expect(body).to have_key('routing')
      expect(body).to have_key('retrieval')
      expect(body).to have_key('tools')
      expect(body).to have_key('orchestration')
      expect(body).to have_key('memory')
      expect(body).to have_key('composition')
      expect(body).to have_key('response')
      expect(body).to have_key('debug')
      expect(body).to have_key('audit')

      expect(body['input']['message']).to eq('What is a refund?')
      expect(body['response']['reply']).to be_present
      expect(body['routing']['agent']).to be_present
    end

    it 'omits sensitive fields from audit and response' do
      merchant, _key = create_merchant_with_api_key
      stub_retrieval!
      stub_groq!

      post dev_ai_playground_run_path,
           params: { message: 'Hello', merchant_id: merchant.id },
           headers: { 'Accept' => 'application/json', 'X-CSRF-Token' => csrf_token },
           as: :json

      body_str = response.parsed_body.to_json
      expect(body_str).not_to include('api_key')
      expect(body_str).not_to include('password')
      expect(body_str).not_to include('secret')
    end

    it 'returns 404 when not in development or test' do
      merchant, _key = create_merchant_with_api_key
      allow(Rails.env).to receive(:development?).and_return(false)
      allow(Rails.env).to receive(:test?).and_return(false)

      post dev_ai_playground_run_path,
           params: { message: 'Hello', merchant_id: merchant.id },
           headers: { 'Accept' => 'application/json', 'X-CSRF-Token' => csrf_token },
           as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
