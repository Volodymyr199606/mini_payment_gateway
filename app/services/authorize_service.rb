# frozen_string_literal: true

require 'timeout'

class AuthorizeService < BaseService
  include WebhookTriggerable
  include Auditable

  def initialize(payment_intent:, idempotency_key: nil)
    super()
    @payment_intent = payment_intent
    @idempotency_key = idempotency_key
  end

  def call
    # Validate state
    unless @payment_intent.status == 'created'
      add_error("Payment intent must be in 'created' state to authorize")
      return self
    end

    success = false
    processor_failure_code = nil
    processor_failure_message = nil
    begin
      success = Timeout.timeout(processor_timeout_seconds) { simulate_processor_authorization }
    rescue Timeout::Error
      processor_failure_code = 'timeout'
      processor_failure_message = 'Processor request timed out'
    end

    failure_code = success ? nil : (processor_failure_code || 'insufficient_funds')
    failure_message = success ? nil : (processor_failure_message || 'Insufficient funds')

    ActiveRecord::Base.transaction do
      transaction = @payment_intent.transactions.create!(
        kind: 'authorize',
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
          kind: 'authorize',
          timeout_seconds: processor_timeout_seconds
        )
      end

      if success
        @payment_intent.update!(status: 'authorized')

        # No ledger charge on authorize – funds are held, not settled.
        # Charge is created only on capture (when money actually moves to merchant).

        # Create audit log
        create_audit_log(
          action: 'payment_authorized',
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
        @payment_intent.update!(status: 'failed')

        # Create audit log
        create_audit_log(
          action: 'payment_authorization_failed',
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
    add_error('Authorization failed')
    @payment_intent.update!(status: 'failed') if @payment_intent.status == 'created'
    self
  end

  private

  def simulate_processor_authorization
    # Simulate 90% success rate for sandbox
    # In production, this would call the actual payment processor
    rand > 0.1
  end
end
