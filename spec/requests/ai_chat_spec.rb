# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'AI chat API', type: :request do
  describe 'POST /api/v1/ai/chat' do
    it 'requires X-API-KEY' do
      post '/api/v1/ai/chat', params: { message: 'How do I refund?' }, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['error']['code']).to eq('unauthorized')
    end

    it 'returns reply, agent, and citations when authenticated' do
      _m, api_key = create_merchant_with_api_key
      stub_groq_and_retriever!

      post '/api/v1/ai/chat',
           params: { message: 'How do refunds work?' },
           headers: api_headers(api_key),
           as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to have_key('reply')
      expect(body).to have_key('agent')
      expect(body['agent']).to be_a(String)
      expect(body).to have_key('citations')
      expect(body['citations']).to be_a(Array)
    end

    def stub_groq_and_retriever!
      client = instance_double(Ai::GroqClient, chat: { content: 'Stubbed reply.' })
      allow(Ai::GroqClient).to receive(:new).and_return(client)
    end

    it 'returns 400 when message is blank' do
      _m, api_key = create_merchant_with_api_key
      post '/api/v1/ai/chat',
           params: { message: '   ' },
           headers: api_headers(api_key),
           as: :json
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body['error']['code']).to eq('validation_error')
    end

    it 'returns reporting_calculation agent and data.totals for "How much in fees last 7 days?"' do
      _m, api_key = create_merchant_with_api_key
      post '/api/v1/ai/chat',
           params: { message: 'How much in fees last 7 days?' },
           headers: api_headers(api_key),
           as: :json
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['agent']).to eq('reporting_calculation')
      expect(body).to have_key('data')
      expect(body['data']).to have_key('totals')
      expect(body['data']['totals']).to include('charges_cents', 'refunds_cents', 'fees_cents', 'net_cents')
      expect(body).to have_key('reply')
    end
  end
end
