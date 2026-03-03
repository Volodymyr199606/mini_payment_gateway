# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Dashboard AI chat', type: :request do
  def csrf_token
    get dashboard_sign_in_path
    follow_redirect! while response.redirect?
    response.body[/name="csrf-token" content="([^"]+)"/, 1] || response.body[/name="authenticity_token" value="([^"]+)"/, 1]
  end

  def post_chat(message, csrf: nil)
    tok = csrf || csrf_token
    post dashboard_ai_chat_path,
         params: { message: message },
         headers: {
           'Accept' => 'application/json',
           'X-CSRF-Token' => tok
         },
         as: :json
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

    it 'returns 400 with JSON error for blank message' do
      _m, key = create_merchant_with_api_key
      post dashboard_sign_in_path, params: { api_key: key, authenticity_token: csrf_token }
      follow_redirect! if response.redirect?
      post_chat('')
      expect(response).to have_http_status(:bad_request)
      expect(response.content_type).to include('application/json')
      expect(response.parsed_body['error']).to eq('message_required')
    end

    it 'returns 200 and reply, agent, citations for valid message when signed in' do
      _m, key = create_merchant_with_api_key
      post dashboard_sign_in_path, params: { api_key: key, authenticity_token: csrf_token }
      follow_redirect! if response.redirect?

      allow(Ai::GroqClient).to receive(:new).and_return(
        instance_double(Ai::GroqClient, chat: { content: 'Stubbed reply.', model_used: 'test', fallback_used: false })
      )

      post_chat('What is authorize vs capture?')
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include('application/json')
      body = response.parsed_body
      expect(body).to have_key('reply')
      expect(body).to have_key('agent')
      expect(body).to have_key('citations')
      expect(body).to have_key('model_used')
      expect(body).to have_key('fallback_used')
      expect(body['citations']).to be_a(Array)
    end

    it 'accepts form-encoded message and returns JSON' do
      _m, key = create_merchant_with_api_key
      post dashboard_sign_in_path, params: { api_key: key, authenticity_token: csrf_token }
      follow_redirect! if response.redirect?

      allow(Ai::GroqClient).to receive(:new).and_return(
        instance_double(Ai::GroqClient, chat: { content: 'OK.', model_used: 'test', fallback_used: false })
      )

      tok = csrf_token
      post dashboard_ai_chat_path,
           params: { message: 'Hello', authenticity_token: tok },
           headers: { 'Accept' => 'application/json', 'X-CSRF-Token' => tok }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['reply']).to eq('OK.')
    end

    it 'includes prior turns in follow-up so LLM receives conversation history' do
      _m, key = create_merchant_with_api_key
      post dashboard_sign_in_path, params: { api_key: key, authenticity_token: csrf_token }
      follow_redirect! if response.redirect?

      first_reply = 'Authorize holds funds; capture settles them.'
      follow_up_reply = 'Yes, exactly as I explained.'

      chat_calls = []
      client = instance_double(Ai::GroqClient)
      allow(client).to receive(:chat) do |messages:, **_kwargs|
        chat_calls << messages
        call_idx = chat_calls.size - 1
        { content: call_idx.zero? ? first_reply : follow_up_reply, model_used: 'test', fallback_used: false }
      end
      allow(Ai::GroqClient).to receive(:new).and_return(client)

      post_chat('What is the difference between authorize and capture?')
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['reply']).to eq(first_reply)

      post_chat('So capture creates a ledger entry?')
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['reply']).to eq(follow_up_reply)

      expect(chat_calls.size).to eq(2)
      follow_up_messages = chat_calls.last
      message_contents = follow_up_messages.map { |m| m[:content] || m['content'] }.join(' ')
      expect(message_contents).to include('What is the difference between authorize and capture')
      expect(message_contents).to include('Authorize holds funds')
      expect(message_contents).to include('So capture creates a ledger entry')
    end

    it 'finds or creates AiChatSession for the merchant and persists user message' do
      merchant, key = create_merchant_with_api_key
      post dashboard_sign_in_path, params: { api_key: key, authenticity_token: csrf_token }
      follow_redirect! if response.redirect?

      allow(Ai::GroqClient).to receive(:new).and_return(
        instance_double(Ai::GroqClient, chat: { content: 'OK', model_used: 'test', fallback_used: false })
      )

      expect { post_chat('Hello') }.to change(AiChatSession, :count).by(1).and change(AiChatMessage, :count).by(2)

      session = merchant.ai_chat_sessions.reload.last
      expect(session).to be_present
      user_msg = session.ai_chat_messages.find_by(role: 'user')
      expect(user_msg).to be_present
      expect(user_msg.content).to eq('Hello')
    end

    it 'includes Memory section when session already has messages' do
      merchant, key = create_merchant_with_api_key
      post dashboard_sign_in_path, params: { api_key: key, authenticity_token: csrf_token }
      follow_redirect! if response.redirect?

      chat_calls = []
      client = instance_double(Ai::GroqClient)
      allow(client).to receive(:chat) do |messages:, **_kwargs|
        chat_calls << messages
        { content: 'Follow-up reply.', model_used: 'test', fallback_used: false }
      end
      allow(Ai::GroqClient).to receive(:new).and_return(client)

      post_chat('What is authorize?')
      expect(response).to have_http_status(:ok)

      post_chat('And capture?')
      expect(response).to have_http_status(:ok)

      expect(chat_calls.size).to eq(2)
      follow_up_messages = chat_calls.last
      system_msg = follow_up_messages.find { |m| (m[:role] || m['role']) == 'system' }
      expect(system_msg).to be_present
      system_content = (system_msg[:content] || system_msg['content']).to_s
      expect(system_content).to include('Memory:')
      expect(system_content).to include('What is authorize?')
      expect(system_content).to include('Follow-up reply.')
    end

    it 'POST /dashboard/ai/chat_sessions/reset creates fresh session and returns ok when signed in' do
      merchant, key = create_merchant_with_api_key
      post dashboard_sign_in_path, params: { api_key: key, authenticity_token: csrf_token }
      follow_redirect! if response.redirect?
      tok = csrf_token

      expect { post dashboard_reset_ai_chat_session_path, headers: { 'Accept' => 'application/json', 'X-CSRF-Token' => tok }, params: {} }
        .to change { merchant.ai_chat_sessions.reload.count }.by(1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['ok']).to be true
      expect(AiChatSession.where(merchant: merchant).count).to be >= 1
    end

    it 'persists assistant reply as AiChatMessage on the same session' do
      merchant, key = create_merchant_with_api_key
      post dashboard_sign_in_path, params: { api_key: key, authenticity_token: csrf_token }
      follow_redirect! if response.redirect?

      allow(Ai::GroqClient).to receive(:new).and_return(
        instance_double(Ai::GroqClient, chat: { content: 'Stubbed reply.', model_used: 'test', fallback_used: false })
      )

      post_chat('What is a refund?')

      session = merchant.ai_chat_sessions.reload.last
      expect(session.ai_chat_messages.count).to eq(2)
      expect(session.ai_chat_messages.pluck(:role)).to match_array(%w[user assistant])
      assistant_msg = session.ai_chat_messages.find_by(role: 'assistant')
      expect(assistant_msg.content).to eq('Stubbed reply.')
    end
  end
end
