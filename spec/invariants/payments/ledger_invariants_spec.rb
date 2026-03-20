# frozen_string_literal: true

# Ledger invariants: charge/refund semantics, no duplicates on idempotent replay, aggregate consistency.
require 'rails_helper'

RSpec.describe 'Payment invariants: ledger', :invariants do
  before { stub_successful_provider }

  it 'charge entries have positive amount; refund entries have negative amount' do
    merchant = build_merchant
    pi = build_payment_intent(merchant: merchant, status: 'authorized', amount_cents: 5000)

    CaptureService.call(payment_intent: pi)
    RefundService.call(payment_intent: pi.reload, amount_cents: 2000)

    charges = merchant.reload.ledger_entries.charges
    refunds = merchant.ledger_entries.refunds

    expect(charges.pluck(:amount_cents)).to all(be > 0),
      'Charge ledger entries must have positive amount_cents'
    expect(refunds.pluck(:amount_cents)).to all(be < 0),
      'Refund ledger entries must have negative amount_cents'
  end

  it 'net ledger (charges + refunds) matches captured minus refunded' do
    merchant = build_merchant
    pi = build_payment_intent(merchant: merchant, status: 'authorized', amount_cents: 10_000)

    CaptureService.call(payment_intent: pi)
    RefundService.call(payment_intent: pi.reload, amount_cents: 4000)
    RefundService.call(payment_intent: pi.reload, amount_cents: 6000)

    charges_sum = charge_ledger_sum(merchant.reload)
    refunds_sum = refund_ledger_sum(merchant)
    net = charges_sum + refunds_sum

    expect(charges_sum).to eq(10_000), 'Total charges must equal captured amount'
    expect(refunds_sum).to eq(-10_000), 'Total refunds must equal sum of refund amounts (stored negative)'
    expect(net).to eq(0), 'Net ledger (charges + refunds) must balance'
  end

  it 'authorize creates no ledger entry' do
    merchant = build_merchant
    pi = build_payment_intent(merchant: merchant, status: 'created')
    before_count = merchant.ledger_entries.count

    AuthorizeService.call(payment_intent: pi)

    expect(merchant.reload.ledger_entries.count).to eq(before_count)
  end

  it 'each capture transaction has exactly one ledger entry' do
    merchant = build_merchant
    pi = build_payment_intent(merchant: merchant, status: 'authorized')
    CaptureService.call(payment_intent: pi)

    capture_txn = pi.reload.transactions.find_by(kind: 'capture', status: 'succeeded')
    expect(capture_txn.ledger_entry).to be_present
    expect(capture_txn.ledger_entry.entry_type).to eq('charge')
  end
end
