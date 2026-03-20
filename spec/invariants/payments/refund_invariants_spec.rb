# frozen_string_literal: true

# Refund invariants: amount limits, state, cumulative refund ceiling.
require 'rails_helper'

RSpec.describe 'Payment invariants: refund', :invariants do
  before { stub_successful_provider }

  it 'refund from captured enforces refundable_cents ceiling' do
    merchant = build_merchant
    pi = build_payment_intent(merchant: merchant, status: 'captured', amount_cents: 5000)

    result = RefundService.call(payment_intent: pi, amount_cents: 6000)

    expect(result).not_to be_success
    expect(result.errors.join).to include('exceeds')
    expect(pi.reload.transactions.where(kind: 'refund').count).to eq(0)
  end

  it 'cumulative refunds cannot exceed captured amount' do
    merchant = build_merchant
    pi = build_payment_intent(merchant: merchant, status: 'captured', amount_cents: 10_000)

    RefundService.call(payment_intent: pi, amount_cents: 4000)
    RefundService.call(payment_intent: pi.reload, amount_cents: 4000)
    third = RefundService.call(payment_intent: pi.reload, amount_cents: 3000)

    expect(third).not_to be_success
    expect(third.errors.join).to include('exceeds')
    expect(pi.reload.total_refunded_cents).to eq(8000)
  end

  it 'refund from authorized is rejected' do
    pi = build_payment_intent(merchant: build_merchant, status: 'authorized')
    result = RefundService.call(payment_intent: pi, amount_cents: 1000)

    expect(result).not_to be_success
    expect(result.errors.join).to include('captured')
  end

  it 'refund creates negative ledger entry matching amount' do
    merchant = build_merchant
    pi = build_payment_intent(merchant: merchant, status: 'captured', amount_cents: 5000)
    before_refunds = refund_ledger_sum(merchant)

    RefundService.call(payment_intent: pi, amount_cents: 2000)

    after_refunds = refund_ledger_sum(merchant.reload)
    expect(after_refunds - before_refunds).to eq(-2000),
      'Refund ledger entry must be negative and match refund amount'
  end

  it 'refundable_cents decreases correctly after partial refund' do
    merchant = build_merchant
    pi = build_payment_intent(merchant: merchant, status: 'captured', amount_cents: 10_000)

    expect(pi.refundable_cents).to eq(10_000)

    RefundService.call(payment_intent: pi, amount_cents: 3000)
    expect(pi.reload.refundable_cents).to eq(7000)

    RefundService.call(payment_intent: pi, amount_cents: 7000)
    expect(pi.reload.refundable_cents).to eq(0)
  end
end
