# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Dashboard AI chat', type: :request do
  def csrf_token
    get dashboard_sign_in_path
    response.body[/name="csrf-token" content="([^"]+)"/, 1] || response.body[/name="authenticity_token" value="([^"]+)"/, 1]
  end

  def post_chat(message, csrf: nil)
    tok = csrf || csrf_token
    post dashboard_ai_chat_path,
         params: { message: message }.to_json,
         headers: {
           'Content-Type' => 'application/json',
           'Accept' => 'application/json',
           'X-CSRF-Token' => tok
         }
  end

  describe 'GET /dashboard/ai' do
    it 'redirects to sign-in when not signed in' do
      get dashboard_ai_path
      expect(response).to redirect_to(dashboard_sign_in_path)
    end

    it 'returns 200 when signed in' do
      _m, key = create_merchant_with_api_key
      post dashboard_sign_in_path, params: { api_key: key, authenticity_token: csrf_token }
      follow_redirect! if response.redirect?
      get dashboard_ai_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST /dashboard/ai/chat' do
    it 'redirects to sign-in when not signed in' do
      post_chat('Hello')
      expect(response).to redirect_to(dashboard_sign_in_path)
    end

    it 'returns 422 for blank message' do
      _m, key = create_merchant_with_api_key
      post dashboard_sign_in_path, params: { api_key: key, authenticity_token: csrf_token }
      follow_redirect! if response.redirect?
      post_chat('')
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('message_required')
    end

    it 'returns 200 and reply, agent, citations for valid message when signed in' do
      _m, key = create_merchant_with_api_key
      post dashboard_sign_in_path, params: { api_key: key, authenticity_token: csrf_token }
      follow_redirect! if response.redirect?

      allow(Ai::GroqClient).to receive(:new).and_return(
        instance_double(Ai::GroqClient, chat: { content: 'Stubbed reply.' })
      )

      post_chat('What is authorize vs capture?')
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to have_key('reply')
      expect(body).to have_key('agent')
      expect(body).to have_key('citations')
      expect(body['citations']).to be_a(Array)
    end
  end
end
