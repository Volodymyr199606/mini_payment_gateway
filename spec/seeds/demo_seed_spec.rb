# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Demo seed' do
  before do
    begin
      skip 'Test DB schema required (run: rails db:test:prepare)' unless ActiveRecord::Base.connection.table_exists?('merchants')
    rescue ActiveRecord::StatementInvalid
      skip 'Test DB schema required (e.g. PostgreSQL with vector extension)'
    end
    require Rails.root.join('db/seeds/demo')
    Seeds::Demo.run(api_keys: {})
  end

  it 'creates the primary demo merchant' do
    merchant = Merchant.find_by(email: Seeds::Demo::DEMO_EMAIL)
    expect(merchant).to be_present
    expect(merchant.name).to eq('Demo Store Inc')
    expect(merchant.status).to eq('active')
  end

  it 'creates the scoping merchant for multi-tenant demos' do
    merchant = Merchant.find_by(email: Seeds::Demo::SCOPING_EMAIL)
    expect(merchant).to be_present
    expect(merchant.name).to eq('Scoping Test Ltd')
  end

  it 'seeds payment intents covering key states' do
    demo = Merchant.find_by(email: Seeds::Demo::DEMO_EMAIL)
    statuses = demo.payment_intents.pluck(:status).uniq
    expect(statuses).to include('created', 'authorized', 'captured', 'failed', 'canceled')
    expect(demo.payment_intents.where(status: 'captured').count).to be >= 2
  end

  it 'seeds ledger entries for reporting' do
    demo = Merchant.find_by(email: Seeds::Demo::DEMO_EMAIL)
    expect(demo.ledger_entries.charges.count).to be >= 1
    expect(demo.ledger_entries.refunds.count).to be >= 1
  end

  it 'seeds webhook events with mixed delivery states' do
    demo = Merchant.find_by(email: Seeds::Demo::DEMO_EMAIL)
    expect(demo.webhook_events.exists?(delivery_status: 'succeeded')).to be true
    expect(demo.webhook_events.exists?(delivery_status: 'failed')).to be true
    expect(demo.webhook_events.exists?(delivery_status: 'pending')).to be true
  end

  it 'returns a summary with notable IDs' do
    summary = Seeds::Demo.summary
    expect(summary).to be_a(Hash)
    expect(summary[:demo_email]).to eq(Seeds::Demo::DEMO_EMAIL)
    expect(summary[:payment_intent_authorized]).to be_present
    expect(summary[:payment_intent_failed]).to be_present
    expect(summary[:transaction_capture]).to be_present
    expect(summary[:webhook_succeeded]).to be_present
    expect(summary[:scoping_email]).to eq(Seeds::Demo::SCOPING_EMAIL)
  end

  it 'keeps demo and scoping data isolated' do
    demo = Merchant.find_by(email: Seeds::Demo::DEMO_EMAIL)
    scoping = Merchant.find_by(email: Seeds::Demo::SCOPING_EMAIL)
    expect(demo.payment_intents.pluck(:id)).not_to include(*scoping.payment_intents.pluck(:id))
  end
end
