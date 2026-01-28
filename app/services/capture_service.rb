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
    unless @payment_intent.status == "authorized"
      add_error("Payment intent must be in 'authorized' state to capture")
      return self
    end

    # Check if already captured
    existing_capture = @payment_intent.transactions.where(kind: "capture", status: "succeeded").first
    if existing_capture
      add_error("Payment intent has already been captured")
      return self
    end

    # Simulate processor capture
    success = simulate_processor_capture

    ActiveRecord::Base.transaction do
      transaction = @payment_intent.transactions.create!(
        kind: "capture",
        status: success ? "succeeded" : "failed",
        amount_cents: @payment_intent.amount_cents,
        failure_code: success ? nil : "capture_failed",
        failure_message: success ? nil : "Capture failed"
      )

      if success
        @payment_intent.update!(status: "captured")
        
        # Create ledger entry for capture (charge)
        LedgerService.call(
          merchant: @payment_intent.merchant,
          transaction: transaction,
          entry_type: "charge",
          amount_cents: @payment_intent.amount_cents,
          currency: @payment_intent.currency
        )

        # Create audit log
        create_audit_log(
          action: "payment_captured",
          auditable: transaction,
          metadata: {
            payment_intent_id: @payment_intent.id,
            amount_cents: transaction.amount_cents,
            status: "succeeded"
          }
        )

        # Trigger webhook event
        trigger_webhook_event(
          event_type: "transaction.succeeded",
          transaction: transaction,
          payment_intent: @payment_intent
        )
      else
        # Create audit log
        create_audit_log(
          action: "payment_capture_failed",
          auditable: transaction,
          metadata: {
            payment_intent_id: @payment_intent.id,
            amount_cents: transaction.amount_cents,
            status: "failed",
            failure_code: transaction.failure_code
          }
        )
        
        # Trigger webhook event for failure
        trigger_webhook_event(
          event_type: "transaction.failed",
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
    add_error("Capture failed: #{e.message}")
    self
  end

  private

  def simulate_processor_capture
    # Simulate 95% success rate for sandbox
    rand > 0.05
  end
end
