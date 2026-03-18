# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Dashboard AI audit trail', type: :request do
  include ActiveJob::TestHelper
  def stub_retrieval_service!
    allow(Ai::Rag::RetrievalService).to receive(:call).and_return(
      context_text: 'Stubbed context.',
      citations: [{ file: 'docs/X.md', heading: 'Y' }],
      context_truncated: false,
      final_sections_count: 1
    )
  end

  def csrf_token
    get dashboard_sign_in_path
    follow_redirect! while response.redirect?
    response.body[/name="csrf-token" content="([^"]+)"/, 1] || response.body[/name="authenticity_token" value="([^"]+)"/, 1]
  end

  def post_chat(message)
    post dashboard_ai_chat_path,
         params: { message: message },
         headers: { 'Accept' => 'application/json', 'X-CSRF-Token' => csrf_token },
         as: :json
  end

  it 'creates an audit record on successful AI request (agent path)' do
    merchant, key = create_merchant_with_api_key
    post dashboard_sign_in_path, params: { api_key: key, authenticity_token: csrf_token }
    follow_redirect! if response.redirect?

    stub_retrieval_service!
    allow(Ai::GroqClient).to receive(:new).and_return(
      instance_double(Ai::GroqClient, chat: { content: 'OK.', model_used: 'test', fallback_used: false })
    )

    expect { post_chat('What is authorize?') }.to change(AiRequestAudit, :count).by(1)

    expect(response).to have_http_status(:ok)
    audit = AiRequestAudit.last
    expect(audit.request_id).to be_present
    expect(audit.endpoint).to eq('dashboard')
    expect(audit.merchant_id).to eq(merchant.id)
    expect(audit.agent_key).to be_present
    expect(audit.success).to be(true)
  end

  it 'creates an audit record on tool path success' do
    merchant, key = create_merchant_with_api_key
    post dashboard_sign_in_path, params: { api_key: key, authenticity_token: csrf_token }
    follow_redirect! if response.redirect?

    post_chat('Show my account info')
    expect(response).to have_http_status(:ok)

    audit = AiRequestAudit.last
    expect(audit).to be_present
    expect(audit.tool_used).to be(true)
    expect(audit.success).to be(true)
  end

  it 'creates a failure audit record when request errors' do
    merchant, key = create_merchant_with_api_key
    post dashboard_sign_in_path, params: { api_key: key, authenticity_token: csrf_token }
    follow_redirect! if response.redirect?

    stub_retrieval_service!
    agent_class = Ai::AgentRegistry.fetch(Ai::Router.new('Hello').call)
    allow_any_instance_of(agent_class).to receive(:call).and_raise(StandardError.new('Simulated failure'))

    post_chat('Hello')
    expect(response).to have_http_status(:internal_server_error)

    audit = AiRequestAudit.last
    expect(audit).to be_present
    expect(audit.success).to be(false)
    expect(audit.error_class).to eq('StandardError')
    expect(audit.error_message).to include('Simulated')
  end

  it 'does not break response when audit persistence fails' do
    merchant, key = create_merchant_with_api_key
    post dashboard_sign_in_path, params: { api_key: key, authenticity_token: csrf_token }
    follow_redirect! if response.redirect?

    stub_retrieval_service!
    allow(Ai::GroqClient).to receive(:new).and_return(
      instance_double(Ai::GroqClient, chat: { content: 'OK.', model_used: 'test', fallback_used: false })
    )
    allow(AiRequestAudit).to receive(:create!).and_raise(ActiveRecord::StatementInvalid.new('DB down'))

    post_chat('What is authorize?')
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to have_key('reply')
    expect(response.parsed_body['reply']).to be_present
  end
end

RSpec.describe 'API AI audit trail', type: :request do
  def stub_retrieval_service!
    allow(Ai::Rag::RetrievalService).to receive(:call).and_return(
      context_text: 'Stubbed context.',
      citations: [{ file: 'docs/X.md', heading: 'Y' }],
      context_truncated: false,
      final_sections_count: 1
    )
  end

  def csrf_token
    get dashboard_sign_in_path
    follow_redirect! while response.redirect?
    response.body[/name="csrf-token" content="([^"]+)"/, 1] || response.body[/name="authenticity_token" value="([^"]+)"/, 1]
  end

  def post_chat(message)
    post dashboard_ai_chat_path,
         params: { message: message },
         headers: { 'Accept' => 'application/json', 'X-CSRF-Token' => csrf_token },
         as: :json
  end

  def api_headers(api_key)
    { 'X-API-KEY' => api_key, 'Content-Type' => 'application/json', 'Accept' => 'application/json' }
  end

  it 'creates an audit record on successful API AI request' do
    merchant, api_key = create_merchant_with_api_key
    allow(Ai::Rag::RetrievalService).to receive(:call).and_return(
      context_text: 'Stubbed context.',
      citations: [{ file: 'docs/X.md', heading: 'Y' }],
      context_truncated: false,
      final_sections_count: 1
    )
    allow(Ai::GroqClient).to receive(:new).and_return(
      instance_double(Ai::GroqClient, chat: { content: 'API reply.', model_used: 'test', fallback_used: false })
    )

    expect {
      post '/api/v1/ai/chat',
           params: { message: 'What is authorize?' },
           headers: api_headers(api_key),
           as: :json
    }.to change(AiRequestAudit, :count).by(1)

    expect(response).to have_http_status(:ok)
    audit = AiRequestAudit.last
    expect(audit.endpoint).to eq('api')
    expect(audit.merchant_id).to eq(merchant.id)
    expect(audit.success).to be(true)
  end

  describe 'async summary refresh' do
    it 'enqueues RefreshConversationSummaryJob on successful dashboard chat (agent path)' do
      merchant, key = create_merchant_with_api_key
      post dashboard_sign_in_path, params: { api_key: key, authenticity_token: csrf_token }
      follow_redirect! if response.redirect?

      stub_retrieval_service!
      allow(Ai::GroqClient).to receive(:new).and_return(
        instance_double(Ai::GroqClient, chat: { content: 'OK.', model_used: 'test', fallback_used: false })
      )

      expect {
        post_chat('What is authorize?')
      }.to have_enqueued_job(Ai::RefreshConversationSummaryJob)

      expect(response).to have_http_status(:ok)
    end

    it 'returns 200 when summary refresh enqueue fails (non-blocking)' do
      merchant, key = create_merchant_with_api_key
      post dashboard_sign_in_path, params: { api_key: key, authenticity_token: csrf_token }
      follow_redirect! if response.redirect?

      stub_retrieval_service!
      allow(Ai::GroqClient).to receive(:new).and_return(
        instance_double(Ai::GroqClient, chat: { content: 'OK.', model_used: 'test', fallback_used: false })
      )
      allow(Ai::Async::SummaryRefreshEnqueuer).to receive(:enqueue_if_ok).and_raise(StandardError.new('Redis down'))

      post_chat('What is authorize?')
      expect(response).to have_http_status(:ok)
    end
  end
end
