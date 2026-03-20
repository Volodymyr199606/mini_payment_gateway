# frozen_string_literal: true

# Helpers for payment invariants suite. Keeps fixture setup readable and assertions explicit.
module InvariantsPaymentHelpers
  def build_merchant
    Merchant.create_with_api_key(
      name: "Invariant Merchant #{SecureRandom.hex(4)}",
      status: 'active',
      email: "inv_#{SecureRandom.hex(4)}@example.com",
      password: 'password123',
      password_confirmation: 'password123'
    ).first
  end

  def build_payment_intent(merchant:, status: 'created', amount_cents: 5000, **opts)
    cust = opts[:customer] || Customer.create!(merchant: merchant, email: "cust_#{SecureRandom.hex(4)}@example.com")
    pm = opts[:payment_method] || PaymentMethod.create!(
      customer: cust,
      method_type: 'card',
      last4: '4242',
      brand: 'Visa',
      exp_month: 12,
      exp_year: 2026
    )
    pi = PaymentIntent.create!(
      merchant: merchant,
      customer: cust,
      payment_method: pm,
      amount_cents: amount_cents,
      currency: opts[:currency] || 'USD',
      status: status
    )
    # Seed transactions for non-created statuses
    if status == 'authorized'
      Transaction.create!(payment_intent: pi, kind: 'authorize', status: 'succeeded', amount_cents: amount_cents)
    elsif status == 'captured'
      Transaction.create!(payment_intent: pi, kind: 'authorize', status: 'succeeded', amount_cents: amount_cents)
      Transaction.create!(payment_intent: pi, kind: 'capture', status: 'succeeded', amount_cents: amount_cents)
    end
    pi
  end

  def stub_successful_provider
    adapter = instance_double(Payments::Providers::BaseAdapter)
    allow(adapter).to receive(:authorize) { Payments::ProviderResult.new(success: true, processor_ref: "sim_auth_#{SecureRandom.hex(8)}") }
    allow(adapter).to receive(:capture) { Payments::ProviderResult.new(success: true, processor_ref: "sim_cap_#{SecureRandom.hex(8)}") }
    allow(adapter).to receive(:void) { Payments::ProviderResult.new(success: true, processor_ref: "sim_void_#{SecureRandom.hex(8)}") }
    allow(adapter).to receive(:refund) { Payments::ProviderResult.new(success: true, processor_ref: "sim_ref_#{SecureRandom.hex(8)}") }
    allow(Payments::ProviderRegistry).to receive(:current).and_return(adapter)
  end

  def charge_ledger_sum(merchant)
    merchant.ledger_entries.charges.sum(:amount_cents)
  end

  def refund_ledger_sum(merchant)
    merchant.ledger_entries.refunds.sum(:amount_cents)
  end
end

RSpec.configure do |config|
  config.include InvariantsPaymentHelpers, file_path: %r{spec/invariants}
end
