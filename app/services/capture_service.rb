# frozen_string_literal: true

require 'timeout'

class CaptureService < BaseService
  include WebhookTriggerable
  include Auditable

  def initialize(payment_intent:, idempotency_key: nil)
    super()
    @payment_intent = payment_intent
    @idempotency_key = idempotency_key
  end

  def call
    # Validate state
    unless @payment_intent.status == 'authorized'
      add_error("Payment intent must be in 'authorized' state to capture")
      return self
    end

    # Check if already captured
    existing_capture = @payment_intent.transactions.where(kind: 'capture', status: 'succeeded').first
    if existing_capture
      add_error('Payment intent has already been captured')
      return self
    end

    success = false
    processor_failure_code = nil
    processor_failure_message = nil
    begin
      success = Timeout.timeout(processor_timeout_seconds) { simulate_processor_capture }
    rescue Timeout::Error
      processor_failure_code = 'timeout'
      processor_failure_message = 'Processor request timed out'
    end

    failure_code = success ? nil : (processor_failure_code || 'capture_failed')
    failure_message = success ? nil : (processor_failure_message || 'Capture failed')

    ActiveRecord::Base.transaction do
      transaction = @payment_intent.transactions.create!(
        kind: 'capture',
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
          kind: 'capture',
          timeout_seconds: processor_timeout_seconds
        )
      end

      if success
        @payment_intent.update!(status: 'captured')

        # Create ledger entry for capture (charge)
        LedgerService.call(
          merchant: @payment_intent.merchant,
          transaction: transaction,
          entry_type: 'charge',
          amount_cents: @payment_intent.amount_cents,
          currency: @payment_intent.currency
        )

        # Create audit log
        create_audit_log(
          action: 'payment_captured',
          auditable: transaction,
          metadata: {
            payment_intent_id: @payment_intent.id,
            amount_cents: transaction.amount_cents,
            status: 'succeeded'
          }
        )

        # Trigger webhook event
        trigger_webhook_event(
          event_type: 'transaction.succeeded',
          transaction: transaction,
          payment_intent: @payment_intent
        )
      else
        # Create audit log
        create_audit_log(
          action: 'payment_capture_failed',
          auditable: transaction,
          metadata: {
            payment_intent_id: @payment_intent.id,
            amount_cents: transaction.amount_cents,
            status: 'failed',
            failure_code: transaction.failure_code
          }
        )

        # Trigger webhook event for failure
        trigger_webhook_event(
          event_type: 'transaction.failed',
          transaction: transaction,
          payment_intent: @payment_intent
        )
      end

      set_result({
                   transaction: transaction,
                   payment_intent: @payment_intent.reload
                 })
    end

    self
  rescue StandardError => e
    add_error('Capture failed')
    self
  end

  private

  def simulate_processor_capture
    # Simulate 95% success rate for sandbox
    rand > 0.05
  end
end
