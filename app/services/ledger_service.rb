# frozen_string_literal: true

class LedgerService < BaseService
  def initialize(merchant:, transaction:, entry_type:, amount_cents:, currency: 'USD')
    super()
    @merchant = merchant
    @transaction = transaction
    @entry_type = entry_type
    @amount_cents = amount_cents
    @currency = currency
  end

  def call
    ledger_entry = LedgerEntry.create!(
      merchant: @merchant,
      payment_transaction: @transaction,
      entry_type: @entry_type,
      amount_cents: @amount_cents,
      currency: @currency
    )

    set_result(ledger_entry)
    self
  rescue StandardError => e
    add_error('ledger_entry_creation_failed')
    raise # Re-raise so parent transaction can roll back
  end
end
