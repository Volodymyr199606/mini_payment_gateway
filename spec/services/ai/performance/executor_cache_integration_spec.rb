# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Ai::Tools::Executor cache integration' do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }
  let(:context) { { merchant_id: merchant.id, request_id: 'test-req' } }

  around do |ex|
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache.lookup_store(:memory_store)
    ex.run
  ensure
    Rails.cache = original
  end

  before do
    allow(Ai::Observability::EventLogger).to receive(:log_tool_call)
    allow(Ai::Observability::EventLogger).to receive(:log_cache)
    allow(Ai::Performance::CachePolicy).to receive(:bypass?).and_return(false)
  end

  it 'returns merchant account data' do
    result = Ai::Tools::Executor.call(tool_name: 'get_merchant_account', args: {}, context: context)
    expect(result[:success]).to be true
    expect(result[:data][:name]).to eq(merchant.name)
  end

  it 'caches get_merchant_account result and returns from cache on second call' do
    Ai::Tools::Executor.call(tool_name: 'get_merchant_account', args: {}, context: context)
    result2 = Ai::Tools::Executor.call(tool_name: 'get_merchant_account', args: {}, context: context)
    expect(result2[:success]).to be true
    expect(result2[:data][:id]).to eq(merchant.id)
    # Cache hit logged
    expect(Ai::Observability::EventLogger).to have_received(:log_cache).with(
      hash_including(cache_outcome: 'hit', cache_category: :merchant_account)
    )
  end

  it 'does not leak cache across merchants' do
    other = create_merchant_with_api_key(name: 'Other').first
    r1 = Ai::Tools::Executor.call(tool_name: 'get_merchant_account', args: {}, context: context)
    r2 = Ai::Tools::Executor.call(tool_name: 'get_merchant_account', args: {}, context: { merchant_id: other.id, request_id: 'r2' })
    expect(r1[:data][:id]).to eq(merchant.id)
    expect(r2[:data][:id]).to eq(other.id)
    expect(r1[:data][:id]).not_to eq(r2[:data][:id])
  end

  it 'bypasses cache when AI_CACHE_BYPASS is set' do
    allow(Ai::Performance::CachePolicy).to receive(:bypass?).and_return(true)
    Ai::Tools::Executor.call(tool_name: 'get_merchant_account', args: {}, context: context)
    Ai::Tools::Executor.call(tool_name: 'get_merchant_account', args: {}, context: context)
    expect(Ai::Observability::EventLogger).not_to have_received(:log_cache).with(hash_including(cache_outcome: 'hit'))
  end

  it 'does not cache get_payment_intent (not cacheable tool)' do
    pi = merchant.payment_intents.create!(
      customer_id: merchant.customers.create!(email: 'c@x.com', merchant_id: merchant.id).id,
      amount_cents: 1000,
      currency: 'USD'
    )
    Ai::Tools::Executor.call(tool_name: 'get_payment_intent', args: { payment_intent_id: pi.id }, context: context)
    Ai::Tools::Executor.call(tool_name: 'get_payment_intent', args: { payment_intent_id: pi.id }, context: context)
    expect(Ai::Observability::EventLogger).not_to have_received(:log_cache)
  end
end
