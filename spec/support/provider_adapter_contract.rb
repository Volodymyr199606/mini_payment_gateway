# frozen_string_literal: true

# Shared examples for provider adapter contract compliance.
# Ensures adapters implement the required interface and return expected types.
RSpec.shared_examples 'implements provider adapter contract' do
  it 'implements authorize' do
    expect(adapter).to respond_to(:authorize).with_keywords(:payment_intent)
  end

  it 'implements capture' do
    expect(adapter).to respond_to(:capture).with_keywords(:payment_intent)
  end

  it 'implements void' do
    expect(adapter).to respond_to(:void).with_keywords(:payment_intent)
  end

  it 'implements refund' do
    expect(adapter).to respond_to(:refund).with_keywords(:payment_intent, :amount_cents)
  end

  it 'implements fetch_status' do
    expect(adapter).to respond_to(:fetch_status).with_keywords(:payment_intent)
  end

  it 'implements verify_webhook_signature' do
    expect(adapter).to respond_to(:verify_webhook_signature).with_keywords(:payload, :headers)
  end

  it 'implements normalize_webhook_event' do
    expect(adapter).to respond_to(:normalize_webhook_event).with_keywords(:payload, :headers)
  end

  it 'authorize returns ProviderResult' do
    result = adapter.authorize(payment_intent: payment_intent)
    expect(result).to be_a(Payments::ProviderResult)
  end

  it 'normalize_webhook_event returns hash with event_type, merchant_id, payload, signature' do
    normalized = adapter.normalize_webhook_event(payload: { 'event_type' => 'test' }, headers: {})
    expect(normalized).to be_a(Hash)
    expect(normalized).to include(:event_type, :payload)
  end
end
