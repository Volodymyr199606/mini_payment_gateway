# frozen_string_literal: true

# Capture invariants: amount, state, double-capture prevention, ledger correctness.
require 'rails_helper'

RSpec.describe 'Payment invariants: capture', :invariants do
  before { stub_successful_provider }

  it 'capture amount equals payment intent amount (no partial capture)' do
    merchant = build_merchant
    pi = build_payment_intent(merchant: merchant, status: 'authorized', amount_cents: 7500)
    result = CaptureService.call(payment_intent: pi)

    expect(result).to be_success
    expect(result.result[:transaction].amount_cents).to eq(7500),
      'Capture transaction amount must equal payment intent amount'
    expect(result.result[:payment_intent].reload.status).to eq('captured')
  end

  it 'capture from created is rejected' do
    pi = build_payment_intent(merchant: build_merchant, status: 'created')
    result = CaptureService.call(payment_intent: pi)

    expect(result).not_to be_success
    expect(result.errors.join).to include('authorized')
    expect(pi.reload.status).to eq('created')
  end

  it 'second capture attempt is rejected (no duplicate capture)' do
    merchant = build_merchant
    pi = build_payment_intent(merchant: merchant, status: 'authorized')
    CaptureService.call(payment_intent: pi)

    second = CaptureService.call(payment_intent: pi.reload)

    expect(second).not_to be_success
    expect(second.errors.join).to match(/already been captured|authorized/),
      'Second capture must be rejected (either as duplicate or wrong state)'
    expect(pi.transactions.where(kind: 'capture', status: 'succeeded').count).to eq(1),
      'Exactly one successful capture transaction must exist'
  end

  it 'capture creates exactly one charge ledger entry' do
    merchant = build_merchant
    pi = build_payment_intent(merchant: merchant, status: 'authorized', amount_cents: 10_000)
    before_charges = charge_ledger_sum(merchant)

    CaptureService.call(payment_intent: pi)

    after_charges = charge_ledger_sum(merchant.reload)
    expect(after_charges - before_charges).to eq(10_000),
      'Capture must create one charge ledger entry equal to payment intent amount'
  end
end
