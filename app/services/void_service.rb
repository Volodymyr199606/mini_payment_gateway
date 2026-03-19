# frozen_string_literal: true

require 'timeout'

class VoidService < BaseService
  include Auditable

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

    provider_result = nil
    processor_failure_code = nil
    processor_failure_message = nil
    begin
      provider_result = Timeout.timeout(processor_timeout_seconds) { payment_provider.void(payment_intent: @payment_intent) }
    rescue Timeout::Error
      processor_failure_code = 'timeout'
      processor_failure_message = 'Processor request timed out'
    rescue Payments::ProviderRequestError => e
      processor_failure_code = 'provider_error'
      processor_failure_message = e.message
    end

    success = provider_result&.success? || false
    failure_code = if success
      nil
    else
      processor_failure_code || provider_result&.failure_code || 'void_failed'
    end
    failure_message = if success
      nil
    else
      processor_failure_message || provider_result&.failure_message || 'Void failed'
    end
    original_status = @payment_intent.status

    ActiveRecord::Base.transaction do
      transaction = @payment_intent.transactions.create!(
        kind: 'void',
        status: success ? 'succeeded' : 'failed',
        amount_cents: @payment_intent.amount_cents,
        processor_ref: provider_result&.processor_ref,
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

        # No ledger entry for void – authorize never created a charge,
        # so there is nothing to reverse. Funds were held, not settled.

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

end
