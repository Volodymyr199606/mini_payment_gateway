# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API rate limiting', type: :request do
  include ApiHelpers

  around do |example|
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache.lookup_store(:memory_store)
    example.run
    Rails.cache = original
  end

  before do
    stub_processor_success
    stub_webhook_delivery
    allow(ApiRateLimits).to receive(:for_category).and_wrap_original do |m, name|
      case name.to_s
      when 'payment_mutation' then { limit: 2, window_seconds: 86_400 }
      when 'read' then { limit: 3, window_seconds: 86_400 }
      when 'ai' then { limit: 2, window_seconds: 86_400 }
      when 'webhook_ingress' then { limit: 1, window_seconds: 86_400 }
      when 'public_registration' then { limit: 2, window_seconds: 86_400 }
      else m.call(name)
      end
    end
  end

  it 'returns 429 with consistent error shape and headers on payment mutation over limit' do
    m, key = create_merchant_with_api_key
    cust = Customer.create!(merchant: m, email: "cust_#{SecureRandom.hex(4)}@example.com")
    pm = PaymentMethod.create!(customer: cust, method_type: 'card', last4: '4242', brand: 'Visa', exp_month: 12, exp_year: 2026)

    2.times do |i|
      post '/api/v1/payment_intents',
           params: {
             payment_intent: {
               customer_id: cust.id,
               payment_method_id: pm.id,
               amount_cents: 1000 + i,
               currency: 'usd',
               idempotency_key: "rl-pi-create-#{i}"
             }
           },
           headers: api_headers(key),
           as: :json
      expect(response).to have_http_status(:created)
    end

    post '/api/v1/payment_intents',
         params: {
           payment_intent: {
             customer_id: cust.id,
             payment_method_id: pm.id,
             amount_cents: 5000,
             currency: 'usd',
             idempotency_key: 'rl-pi-create-over'
           }
         },
         headers: api_headers(key),
         as: :json

    expect(response).to have_http_status(:too_many_requests)
    body = response.parsed_body
    expect(body.dig('error', 'code')).to eq('rate_limited')
    expect(body.dig('error', 'details', 'retry_after_seconds')).to be_present
    expect(response.headers['Retry-After']).to be_present
    expect(response.headers['X-RateLimit-Remaining']).to eq('0')
  end

  it 'does not cross tenant buckets for payment mutations' do
    m_a, key_a = create_merchant_with_api_key(name: 'A', email: "a_#{SecureRandom.hex(4)}@example.com")
    m_b, key_b = create_merchant_with_api_key(name: 'B', email: "b_#{SecureRandom.hex(4)}@example.com")

    [m_a, m_b].each do |merchant|
      cust = Customer.create!(merchant: merchant, email: "c_#{SecureRandom.hex(4)}@example.com")
      pm = PaymentMethod.create!(customer: cust, method_type: 'card', last4: '4242', brand: 'Visa', exp_month: 12, exp_year: 2026)
      api_key = merchant == m_a ? key_a : key_b
      2.times do |i|
        post '/api/v1/payment_intents',
             params: {
               payment_intent: {
                 customer_id: cust.id,
                 payment_method_id: pm.id,
                 amount_cents: 2000 + i,
                 currency: 'usd',
                 idempotency_key: "iso-#{merchant.id}-#{i}"
               }
             },
             headers: api_headers(api_key),
             as: :json
        expect(response).to have_http_status(:created), "merchant #{merchant.id} request #{i}"
      end
    end
  end

  it 'applies a separate higher bucket for read endpoints' do
    m, key = create_merchant_with_api_key
    cust = Customer.create!(merchant: m, email: "cust_#{SecureRandom.hex(4)}@example.com")
    pm = PaymentMethod.create!(customer: cust, method_type: 'card', last4: '4242', brand: 'Visa', exp_month: 12, exp_year: 2026)
    pi = PaymentIntent.create!(merchant: m, customer: cust, payment_method: pm, amount_cents: 1000, currency: 'USD', status: 'created')

    3.times do
      get "/api/v1/payment_intents/#{pi.id}", headers: api_headers(key)
      expect(response).to have_http_status(:ok)
    end

    get "/api/v1/payment_intents/#{pi.id}", headers: api_headers(key)
    expect(response).to have_http_status(:too_many_requests)
  end

  it 'rate limits POST /api/v1/merchants by IP (public registration bucket)' do
    2.times do |i|
      post '/api/v1/merchants',
           params: { merchant: { name: "Bot#{i}", email: "bot#{i}_#{SecureRandom.hex(4)}@example.com", password: 'password123', password_confirmation: 'password123' } },
           as: :json
      expect(response).to have_http_status(:forbidden)
    end

    post '/api/v1/merchants',
         params: { merchant: { name: 'Over', email: "over_#{SecureRandom.hex(4)}@example.com", password: 'password123', password_confirmation: 'password123' } },
         as: :json
    expect(response).to have_http_status(:too_many_requests)
  end

  it 'records ApiRequestStat when merchant-scoped rate limit returns 429 (before_action does not run after_action)' do
    m, key = create_merchant_with_api_key
    cust = Customer.create!(merchant: m, email: "cust_#{SecureRandom.hex(4)}@example.com")
    pm = PaymentMethod.create!(customer: cust, method_type: 'card', last4: '4242', brand: 'Visa', exp_month: 12, exp_year: 2026)

    allow(ApiRequestStat).to receive(:record_request!).and_call_original

    2.times do |i|
      post '/api/v1/payment_intents',
           params: {
             payment_intent: {
               customer_id: cust.id,
               payment_method_id: pm.id,
               amount_cents: 4000 + i,
               currency: 'usd',
               idempotency_key: "stat-#{i}"
             }
           },
           headers: api_headers(key),
           as: :json
      expect(response).to have_http_status(:created)
    end

    post '/api/v1/payment_intents',
         params: {
           payment_intent: {
             customer_id: cust.id,
             payment_method_id: pm.id,
             amount_cents: 9999,
             currency: 'usd',
             idempotency_key: 'stat-over'
           }
         },
         headers: api_headers(key),
         as: :json
    expect(response).to have_http_status(:too_many_requests)
    expect(ApiRequestStat).to have_received(:record_request!).with(hash_including(merchant_id: m.id, is_rate_limited: true)).once
  end

  it 'does not rate limit the public health endpoint' do
    5.times do
      get '/api/v1/health'
      expect(response).to have_http_status(:ok)
    end
  end

  it 'rate limits webhook ingress by IP' do
    adapter = instance_double(Payments::Providers::BaseAdapter)
    allow(adapter).to receive(:verify_webhook_signature).and_return(true)
    allow(adapter).to receive(:normalize_webhook_event).and_return(
      event_type: 'ping',
      merchant_id: nil,
      payload: { event_type: 'ping' },
      signature: 'sig'
    )
    allow(Payments::ProviderRegistry).to receive(:current).and_return(adapter)
    allow(WebhookDeliveryJob).to receive(:perform_later)

    expect(Rails.logger).to receive(:warn).with(/api_rate_limited/).once.and_call_original

    post '/api/v1/webhooks/processor', params: { x: 1 }.to_json, headers: { 'Content-Type' => 'application/json' }
    expect(response).to have_http_status(:created)

    post '/api/v1/webhooks/processor', params: { x: 2 }.to_json, headers: { 'Content-Type' => 'application/json' }
    expect(response).to have_http_status(:too_many_requests)
  end

  it 'rate limits AI chat independently from payment mutation counters' do
    m, api_key = create_merchant_with_api_key
    stub_retrieval = lambda do
      allow(Ai::Rag::RetrievalService).to receive(:call).and_return(
        context_text: 'x' * 120,
        citations: [{ file: 'docs/X.md', heading: 'H', anchor: 'a', excerpt: 'e' }],
        metadata: {}
      )
      allow(Ai::GroqClient).to receive(:new).and_return(
        instance_double(Ai::GroqClient, chat: { content: 'ok' })
      )
    end

    stub_retrieval.call
    2.times do |i|
      post '/api/v1/ai/chat',
           params: { message: "Question #{i}?" },
           headers: api_headers(api_key),
           as: :json
      expect(response).to have_http_status(:ok)
    end

    post '/api/v1/ai/chat',
         params: { message: 'Third question?' },
         headers: api_headers(api_key),
         as: :json
    expect(response).to have_http_status(:too_many_requests)
  end

  it 'logs rate limit events with safe metadata' do
    m, key = create_merchant_with_api_key
    cust = Customer.create!(merchant: m, email: "cust_#{SecureRandom.hex(4)}@example.com")
    pm = PaymentMethod.create!(customer: cust, method_type: 'card', last4: '4242', brand: 'Visa', exp_month: 12, exp_year: 2026)

    expect(Rails.logger).to receive(:warn) do |payload|
      expect(payload).to include('api_rate_limited')
      data = JSON.parse(payload)
      expect(data['event']).to eq('api_rate_limited')
      expect(data['merchant_id']).to eq(m.id)
      expect(data['limiter_category']).to eq('payment_mutation')
      expect(data['limit_exceeded']).to be true
    end.at_least(:once)

    2.times do |i|
      post '/api/v1/payment_intents',
           params: {
             payment_intent: {
               customer_id: cust.id,
               payment_method_id: pm.id,
               amount_cents: 3000 + i,
               currency: 'usd',
               idempotency_key: "log-#{i}"
             }
           },
           headers: api_headers(key),
           as: :json
    end
    post '/api/v1/payment_intents',
         params: {
           payment_intent: {
             customer_id: cust.id,
             payment_method_id: pm.id,
             amount_cents: 9000,
             currency: 'usd',
             idempotency_key: 'log-over'
           }
         },
         headers: api_headers(key),
         as: :json
  end
end
