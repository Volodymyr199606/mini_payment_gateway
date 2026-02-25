# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Reporting::LedgerSummary do
  let(:merchant) { Merchant.create_with_api_key(name: 'Test', status: 'active', email: "test_#{SecureRandom.hex(4)}@example.com", password: 'password1', password_confirmation: 'password1').first }
  let(:from) { 3.days.ago.beginning_of_day }
  let(:to) { Time.current }

  before do
    # Clear ledger entries for this merchant to avoid seed data
    LedgerEntry.where(merchant: merchant).delete_all
  end

  it 'returns zero totals when no entries' do
    result = described_class.new(merchant_id: merchant.id, from: from, to: to).call
    expect(result[:totals][:charges_cents]).to eq(0)
    expect(result[:totals][:refunds_cents]).to eq(0)
    expect(result[:totals][:fees_cents]).to eq(0)
    expect(result[:totals][:net_cents]).to eq(0)
    expect(result[:counts][:captures_count]).to eq(0)
    expect(result[:counts][:refunds_count]).to eq(0)
  end

  it 'sums charge entries (positive) and refund entries (negative), outputs refunds as positive' do
    LedgerEntry.create!(merchant: merchant, entry_type: 'charge', amount_cents: 10_000, currency: 'USD', created_at: 2.days.ago)
    LedgerEntry.create!(merchant: merchant, entry_type: 'charge', amount_cents: 5_000, currency: 'USD', created_at: 1.day.ago)
    LedgerEntry.create!(merchant: merchant, entry_type: 'refund', amount_cents: -3_000, currency: 'USD', created_at: 1.day.ago)
    result = described_class.new(merchant_id: merchant.id, from: from, to: to).call
    expect(result[:totals][:charges_cents]).to eq(15_000)
    expect(result[:totals][:refunds_cents]).to eq(3_000)
    expect(result[:totals][:net_cents]).to eq(12_000)
    expect(result[:counts][:captures_count]).to eq(2)
    expect(result[:counts][:refunds_count]).to eq(1)
  end

  it 'includes fee entries in totals and net' do
    LedgerEntry.create!(merchant: merchant, entry_type: 'charge', amount_cents: 10_000, currency: 'USD', created_at: 2.days.ago)
    LedgerEntry.create!(merchant: merchant, entry_type: 'fee', amount_cents: 100, currency: 'USD', created_at: 2.days.ago)
    result = described_class.new(merchant_id: merchant.id, from: from, to: to).call
    expect(result[:totals][:charges_cents]).to eq(10_000)
    expect(result[:totals][:fees_cents]).to eq(100)
    expect(result[:totals][:net_cents]).to eq(9_900)
  end

  it 'scopes by merchant and time range' do
    other = Merchant.create_with_api_key(name: 'Other', status: 'active', email: "other_#{SecureRandom.hex(4)}@example.com", password: 'password1', password_confirmation: 'password1').first
    LedgerEntry.create!(merchant: merchant, entry_type: 'charge', amount_cents: 10_000, currency: 'USD', created_at: 2.days.ago)
    LedgerEntry.create!(merchant: other, entry_type: 'charge', amount_cents: 99_000, currency: 'USD', created_at: 2.days.ago)
    result = described_class.new(merchant_id: merchant.id, from: from, to: to).call
    expect(result[:totals][:charges_cents]).to eq(10_000)
  end

  it 'returns breakdown when group_by is day' do
    LedgerEntry.create!(merchant: merchant, entry_type: 'charge', amount_cents: 10_000, currency: 'USD', created_at: 2.days.ago)
    LedgerEntry.create!(merchant: merchant, entry_type: 'charge', amount_cents: 5_000, currency: 'USD', created_at: 1.day.ago)
    result = described_class.new(merchant_id: merchant.id, from: from, to: to, group_by: 'day').call
    expect(result[:breakdown]).to be_a(Array)
    expect(result[:breakdown].size).to be >= 1
    expect(result[:breakdown].first).to include(:period, :charges_cents, :refunds_cents, :fees_cents, :net_cents)
  end
end
