# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Provider webhook ingestion', type: :request do
  include ActiveJob::TestHelper
  include ApiHelpers

  it 'rejects webhook when provider signature verification fails' do
    adapter = instance_double(Payments::Providers::BaseAdapter)
    allow(adapter).to receive(:verify_webhook_signature).and_return(false)
    allow(Payments::ProviderRegistry).to receive(:current).and_return(adapter)

    post '/api/v1/webhooks/processor', params: { event_type: 'transaction.succeeded' }.to_json, headers: { 'Content-Type' => 'application/json' }

    expect(response).to have_http_status(:unauthorized)
  end

  it 'normalizes and persists webhook payload via provider adapter' do
    merchant, = create_merchant_with_api_key

    adapter = instance_double(Payments::Providers::BaseAdapter)
    allow(adapter).to receive(:verify_webhook_signature).and_return(true)
    allow(adapter).to receive(:normalize_webhook_event).and_return(
      event_type: 'transaction.succeeded',
      merchant_id: merchant.id,
      payload: { event_type: 'transaction.succeeded', data: { merchant_id: merchant.id, payment_intent_id: 123 } },
      signature: 'sig_123'
    )
    allow(Payments::ProviderRegistry).to receive(:current).and_return(adapter)
    allow(WebhookDeliveryJob).to receive(:perform_later)

    post '/api/v1/webhooks/processor', params: { any: 'payload' }.to_json, headers: { 'Content-Type' => 'application/json' }

    expect(response).to have_http_status(:created)
    event = WebhookEvent.last
    expect(event.event_type).to eq('transaction.succeeded')
    expect(event.merchant_id).to eq(merchant.id)
    expect(event.signature).to eq('sig_123')
  end
end
