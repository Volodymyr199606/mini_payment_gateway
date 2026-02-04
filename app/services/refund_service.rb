class RefundService < BaseService
  include WebhookTriggerable
  include Auditable

  def initialize(payment_intent:, amount_cents: nil, idempotency_key: nil)
    super()
    @payment_intent = payment_intent
    @amount_cents = amount_cents
    @idempotency_key = idempotency_key
  end

  def call
    # Validate state
    unless @payment_intent.status == "captured"
      add_error("Payment intent must be in 'captured' state to refund")
      return self
    end

    # Determine refund amount
    refund_amount = @amount_cents || @payment_intent.refundable_cents

    # Validate refund amount
    if refund_amount <= 0
      add_error("Refund amount must be greater than zero")
      return self
    end

    if refund_amount > @payment_intent.refundable_cents
      add_error("Refund amount exceeds refundable amount")
      return self
    end

    # Simulate processor refund
    success = simulate_processor_refund

    ActiveRecord::Base.transaction do
      transaction = @payment_intent.transactions.create!(
        kind: "refund",
        status: success ? "succeeded" : "failed",
        amount_cents: refund_amount,
        failure_code: success ? nil : "refund_failed",
        failure_message: success ? nil : "Refund failed"
      )

      if success
        # Create ledger entry for refund (negative amount)
        LedgerService.call(
          merchant: @payment_intent.merchant,
          transaction: transaction,
          entry_type: "refund",
          amount_cents: -refund_amount, # Negative for refund
          currency: @payment_intent.currency
        )

        # Create audit log
        create_audit_log(
          action: "payment_refunded",
          auditable: transaction,
          metadata: {
            payment_intent_id: @payment_intent.id,
            amount_cents: refund_amount,
            status: "succeeded",
            refund_type: refund_amount == @payment_intent.refundable_cents ? "full" : "partial"
          }
        )

        # Trigger webhook event
        trigger_webhook_event(
          event_type: "transaction.succeeded",
          transaction: transaction,
          payment_intent: @payment_intent
        )
      else
        # Create audit log for failure
        create_audit_log(
          action: "payment_refund_failed",
          auditable: transaction,
          metadata: {
            payment_intent_id: @payment_intent.id,
            amount_cents: refund_amount,
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
        payment_intent: @payment_intent.reload,
        refund_amount_cents: refund_amount
      })
    end

    self
  rescue StandardError => e
    add_error("Refund failed: #{e.message}")
    self
  end

  private

  def simulate_processor_refund
    # Simulate 99% success rate for sandbox
    rand > 0.01
  end
end
