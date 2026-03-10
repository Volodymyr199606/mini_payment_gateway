# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'AI chat API', type: :request do
  # Fixed retrieval response so tests pass regardless of AI_CONTEXT_GRAPH_ENABLED / AI_VECTOR_RAG_ENABLED.
  # context_text must be >= 80 chars so the agent does not use low-context fallback (no LLM call).
  def stub_retrieval_service!(overrides = {})
    default = {
      context_text: "Stubbed context from docs/REFUNDS.md. This is long enough to exceed LOW_CONTEXT_THRESHOLD so the agent calls the LLM.",
      citations: [
        { file: 'docs/REFUNDS.md', heading: 'Endpoint', anchor: 'endpoint', excerpt: 'Stubbed excerpt.' }
      ],
      metadata: {}
    }
    result = default.merge(overrides)
    allow(Ai::Rag::RetrievalService).to receive(:call).and_return(result)
  end

  describe 'POST /api/v1/ai/chat' do
    it 'requires X-API-KEY' do
      post '/api/v1/ai/chat', params: { message: 'How do I refund?' }, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['error']['code']).to eq('unauthorized')
    end

    it 'returns reply, agent, and citations when authenticated' do
      _m, api_key = create_merchant_with_api_key
      stub_retrieval_service!
      allow(Ai::GroqClient).to receive(:new).and_return(
        instance_double(Ai::GroqClient, chat: { content: 'Stubbed reply.' })
      )

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
      stub_retrieval_service!
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

    it 'returns operational agent and citations from stubbed retrieval for "authorize vs capture"' do
      _m, api_key = create_merchant_with_api_key
      stub_retrieval_service!(
        context_text: "Authorize vs capture from PAYMENT_LIFECYCLE.",
        citations: [
          { file: 'docs/PAYMENT_LIFECYCLE.md', heading: 'Authorize (in this project)', anchor: 'authorize-in-this-project', excerpt: 'Ledger: no entries on authorize.' },
          { file: 'docs/PAYMENT_LIFECYCLE.md', heading: 'Capture (in this project)', anchor: 'capture-in-this-project', excerpt: 'Ledger: charge entry on capture.' }
        ]
      )
      allow(Ai::GroqClient).to receive(:new).and_return(
        instance_double(Ai::GroqClient, chat: { content: 'Authorize holds funds; capture settles. See PAYMENT_LIFECYCLE.' })
      )

      post '/api/v1/ai/chat',
           params: { message: 'What is the difference between authorize and capture?' },
           headers: api_headers(api_key),
           as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['agent']).to eq('operational')
      expect(body['citations']).to be_a(Array)
      citation_files = body['citations'].map { |c| c['file'] || c[:file] }.compact.map(&:to_s)
      expect(citation_files).to include('docs/PAYMENT_LIFECYCLE.md')
    end

    it 'omits debug payload when AI_DEBUG is not enabled' do
      _m, api_key = create_merchant_with_api_key
      stub_retrieval_service!
      allow(Ai::GroqClient).to receive(:new).and_return(
        instance_double(Ai::GroqClient, chat: { content: 'Stubbed reply.' })
      )
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('AI_DEBUG').and_return('false')

      post '/api/v1/ai/chat',
           params: { message: 'How do refunds work?' },
           headers: api_headers(api_key),
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).not_to have_key('debug')
    end

    it 'includes debug payload when AI_DEBUG=true' do
      _m, api_key = create_merchant_with_api_key
      stub_retrieval_service!
      allow(Ai::GroqClient).to receive(:new).and_return(
        instance_double(Ai::GroqClient, chat: { content: 'Stubbed reply.', model_used: 'test', fallback_used: false })
      )
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('AI_DEBUG').and_return('true')
      allow(ENV).to receive(:[]).with('AI_CONTEXT_GRAPH_ENABLED').and_return('')
      allow(ENV).to receive(:[]).with('AI_VECTOR_RAG_ENABLED').and_return('')

      post '/api/v1/ai/chat',
           params: { message: 'How do refunds work?' },
           headers: api_headers(api_key),
           as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to have_key('debug')
      debug = body['debug']
      expect(debug).to have_key('selected_agent')
      expect(debug).to have_key('selected_retriever')
      expect(debug).to have_key('graph_enabled')
      expect(debug).to have_key('vector_enabled')
      expect(debug).to have_key('citations_count')
      expect(debug).to have_key('fallback_used')
      expect(debug).to have_key('citation_reask_used')
      expect(debug).to have_key('model_used')
      expect(debug).to have_key('latency_ms')
    end

    it 'passes stubbed context and citations to agent and returns them in response' do
      _m, api_key = create_merchant_with_api_key
      stub_retrieval_service!(
        context_text: "[docs/PAYMENT_LIFECYCLE.md :: Authorize]\n\n- No ledger on authorize.\n\n[docs/PAYMENT_LIFECYCLE.md :: Capture]\n\n- Charge on capture.",
        citations: [
          { file: 'docs/PAYMENT_LIFECYCLE.md', heading: 'Authorize (in this project)', anchor: 'authorize-in-this-project', excerpt: 'Ledger: no entries on authorize.' },
          { file: 'docs/PAYMENT_LIFECYCLE.md', heading: 'Capture (in this project)', anchor: 'capture-in-this-project', excerpt: 'Ledger: charge entry on capture.' }
        ]
      )
      allow(Ai::GroqClient).to receive(:new).and_return(
        instance_double(Ai::GroqClient, chat: { content: 'In this project, authorize holds funds; capture settles. See PAYMENT_LIFECYCLE.md.' })
      )

      post '/api/v1/ai/chat',
           params: { message: 'What is the difference between authorize and capture?' },
           headers: api_headers(api_key),
           as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['agent']).to eq('operational')
      expect(body['citations'].map { |c| c['file'] || c[:file] }).to include('docs/PAYMENT_LIFECYCLE.md')
    end
  end
end
