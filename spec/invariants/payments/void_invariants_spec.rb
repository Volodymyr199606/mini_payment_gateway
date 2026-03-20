# frozen_string_literal: true

# Void invariants: allowed states, no ledger entry, status transition.
require 'rails_helper'

RSpec.describe 'Payment invariants: void', :invariants do
  before { stub_successful_provider }

  it 'void from authorized transitions to canceled' do
    pi = build_payment_intent(merchant: build_merchant, status: 'authorized')
    result = VoidService.call(payment_intent: pi)

    expect(result).to be_success
    expect(pi.reload.status).to eq('canceled')
  end

  it 'void from created transitions to canceled' do
    pi = build_payment_intent(merchant: build_merchant, status: 'created')
    result = VoidService.call(payment_intent: pi)

    expect(result).to be_success
    expect(pi.reload.status).to eq('canceled')
  end

  it 'void from captured is rejected' do
    pi = build_payment_intent(merchant: build_merchant, status: 'captured')
    result = VoidService.call(payment_intent: pi)

    expect(result).not_to be_success
    expect(result.errors.join).to include('created').or include('authorized')
    expect(pi.reload.status).to eq('captured')
  end

  it 'void creates no ledger entry' do
    merchant = build_merchant
    pi = build_payment_intent(merchant: merchant, status: 'authorized')
    before_count = merchant.ledger_entries.count

    VoidService.call(payment_intent: pi)

    expect(merchant.reload.ledger_entries.count).to eq(before_count),
      'Void must not create any ledger entry'
  end
end
