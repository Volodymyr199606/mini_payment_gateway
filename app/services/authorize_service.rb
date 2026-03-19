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

    provider_result = nil
    processor_failure_code = nil
    processor_failure_message = nil
    begin
      provider_result = Timeout.timeout(processor_timeout_seconds) { payment_provider.authorize(payment_intent: @payment_intent) }
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
      processor_failure_code || provider_result&.failure_code || 'insufficient_funds'
    end
    failure_message = if success
      nil
    else
      processor_failure_message || provider_result&.failure_message || 'Insufficient funds'
    end

    ActiveRecord::Base.transaction do
      transaction = @payment_intent.transactions.create!(
        kind: 'authorize',
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

end
