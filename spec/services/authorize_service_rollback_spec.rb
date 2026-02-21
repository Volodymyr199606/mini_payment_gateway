# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuthorizeService, 'transaction rollback' do
  let(:merchant) do
    _m, = Merchant.create_with_api_key(
      name: 'Test Merchant',
      status: 'active',
      email: "test_#{SecureRandom.hex(4)}@example.com",
      password: 'password123',
      password_confirmation: 'password123'
    )
    Merchant.last
  end

  let(:customer) { Customer.create!(merchant: merchant, email: 'test@example.com') }
  let(:payment_method) do
    PaymentMethod.create!(
      customer: customer,
      method_type: 'card',
      last4: '4242',
      brand: 'Visa',
      exp_month: 12,
      exp_year: 2026
    )
  end

  let(:payment_intent) do
    PaymentIntent.create!(
      merchant: merchant,
      customer: customer,
      payment_method: payment_method,
      amount_cents: 5000,
      currency: 'USD',
      status: 'created'
    )
  end

  it 'rolls back all DB writes when LedgerService raises mid-transaction' do
    payment_intent # ensure setup runs first
    tx_count_before = Transaction.count
    ledger_count_before = LedgerEntry.count
    audit_count_before = AuditLog.count
    webhook_count_before = WebhookEvent.count

    allow(LedgerService).to receive(:call).and_raise(RuntimeError.new('Simulated ledger failure'))

    allow_any_instance_of(AuthorizeService).to receive(:simulate_processor_authorization).and_return(true)

    service = AuthorizeService.call(payment_intent: payment_intent)

    expect(service).not_to be_success
    expect(service.errors).to include(/Authorization failed/)

    payment_intent.reload
    # After rollback, DB state reverts to 'created'; no partial authorized state
    expect(payment_intent.status).to eq('created')

    expect(Transaction.count).to eq(tx_count_before)
    expect(LedgerEntry.count).to eq(ledger_count_before)
    expect(AuditLog.count).to eq(audit_count_before)
    expect(WebhookEvent.count).to eq(webhook_count_before)
  end
end
