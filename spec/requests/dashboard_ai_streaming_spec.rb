# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Dashboard AI streaming', type: :request do
  def stub_retrieval!
    allow(Ai::Rag::RetrievalService).to receive(:call).and_return(
      context_text: 'Stubbed context. This is long enough to exceed LOW_CONTEXT_THRESHOLD so the agent calls the LLM.',
      citations: [{ file: 'docs/X.md', heading: 'Y' }],
      context_truncated: false,
      final_sections_count: 1
    )
  end

  def post_chat(message, stream: false)
    tok = csrf_token
    body = { message: message, agent: 'auto' }
    body[:stream] = true if stream
    post dashboard_ai_chat_path,
         params: body,
         headers: {
           'Accept' => stream ? 'text/event-stream' : 'application/json',
           'X-CSRF-Token' => tok
         },
         as: :json
  end

  def csrf_token
    get dashboard_sign_in_path
    follow_redirect! while response.redirect?
    response.body[/name="csrf-token" content="([^"]+)"/, 1] || response.body[/name="authenticity_token" value="([^"]+)"/, 1]
  end

  context 'when AI_STREAMING_ENABLED is false' do
    before { allow(ENV).to receive(:[]).and_call_original; allow(ENV).to receive(:[]).with('AI_STREAMING_ENABLED').and_return('false') }

    it 'returns JSON for stream=1 requests' do
      _m, key = create_merchant_with_api_key
      post dashboard_sign_in_path, params: { api_key: key, authenticity_token: csrf_token }
      follow_redirect! if response.redirect?

      stub_retrieval!
      allow(Ai::GroqClient).to receive(:new).and_return(
        instance_double(Ai::GroqClient, chat: { content: 'OK.', model_used: 'test', fallback_used: false })
      )

      post_chat('Hello', stream: true)
      expect(response.content_type).to include('application/json')
      expect(response.parsed_body).to have_key('reply')
      expect(response.parsed_body['reply']).to eq('OK.')
    end
  end

  context 'when AI_STREAMING_ENABLED is true' do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('AI_STREAMING_ENABLED').and_return('true')
      allow(ENV).to receive(:[]).with('AI_CONTEXT_GRAPH_ENABLED').and_return('')
      allow(ENV).to receive(:[]).with('AI_VECTOR_RAG_ENABLED').and_return('')
    end

    it 'returns SSE stream for stream=1 requests' do
      _m, key = create_merchant_with_api_key
      post dashboard_sign_in_path, params: { api_key: key, authenticity_token: csrf_token }
      follow_redirect! if response.redirect?

      stub_retrieval!
      allow_any_instance_of(Ai::Generation::StreamingClient).to receive(:stream) do |*_args, &block|
        block&.call('Hello')
        block&.call(' world')
        { content: 'Hello world', model_used: 'test', fallback_used: false }
      end

      post dashboard_ai_chat_path,
           params: { message: 'Hi', agent: 'auto', stream: true },
           headers: { 'Accept' => 'text/event-stream', 'X-CSRF-Token' => csrf_token },
           as: :json

      expect(response.content_type).to include('text/event-stream')
      expect(response.body).to include('event: chunk')
      expect(response.body).to include('event: done')
    end
  end
end
