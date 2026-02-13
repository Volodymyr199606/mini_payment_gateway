# frozen_string_literal: true

require 'timeout'

class VoidService < BaseService
  def initialize(payment_intent:, idempotency_key: nil)
    super()
    @payment_intent = payment_intent
    @idempotency_key = idempotency_key
  end

  def call
    # Validate state
    unless %w[created authorized].include?(@payment_intent.status)
      add_error("Payment intent must be in 'created' or 'authorized' state to void")
      return self
    end

    success = false
    processor_failure_code = nil
    processor_failure_message = nil
    begin
      success = Timeout.timeout(processor_timeout_seconds) { simulate_processor_void }
    rescue Timeout::Error
      processor_failure_code = 'timeout'
      processor_failure_message = 'Processor request timed out'
    end

    failure_code = success ? nil : (processor_failure_code || 'void_failed')
    failure_message = success ? nil : (processor_failure_message || 'Void failed')
    original_status = @payment_intent.status

    ActiveRecord::Base.transaction do
      transaction = @payment_intent.transactions.create!(
        kind: 'void',
        status: success ? 'succeeded' : 'failed',
        amount_cents: @payment_intent.amount_cents,
        failure_code: failure_code,
        failure_message: failure_message
      )

      if !success && processor_failure_code == 'timeout'
        log_processor_timeout(
          merchant_id: @payment_intent.merchant_id,
          payment_intent_id: @payment_intent.id,
          transaction_id: transaction.id,
          kind: 'void',
          timeout_seconds: processor_timeout_seconds
        )
      end

      if success
        @payment_intent.update!(status: 'canceled')

        # Create ledger entry for void (refund of authorization)
        # Only create ledger entry if it was previously authorized (had money held)
        if original_status == 'authorized'
          LedgerService.call(
            merchant: @payment_intent.merchant,
            transaction: transaction,
            entry_type: 'refund',
            amount_cents: -@payment_intent.amount_cents, # Negative for refund
            currency: @payment_intent.currency
          )
        end

        # Create audit log
        create_audit_log(
          action: 'payment_voided',
          auditable: transaction,
          metadata: {
            payment_intent_id: @payment_intent.id,
            amount_cents: transaction.amount_cents,
            status: 'succeeded',
            original_status: original_status
          }
        )
      else
        # Create audit log for failure
        create_audit_log(
          action: 'payment_void_failed',
          auditable: transaction,
          metadata: {
            payment_intent_id: @payment_intent.id,
            amount_cents: transaction.amount_cents,
            status: 'failed',
            failure_code: transaction.failure_code
          }
        )
      end

      set_result({
                   transaction: transaction,
                   payment_intent: @payment_intent.reload
                 })
    end

    self
  rescue StandardError => e
    add_error('Void failed')
    self
  end

  private

  def simulate_processor_void
    # Simulate 98% success rate for sandbox
    rand > 0.02
  end
end
