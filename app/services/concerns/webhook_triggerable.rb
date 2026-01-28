module WebhookTriggerable
  extend ActiveSupport::Concern

  private

  def trigger_webhook_event(event_type:, transaction:, payment_intent:)
    payload = {
      event_type: event_type,
      data: {
        merchant_id: payment_intent.merchant_id,
        payment_intent_id: payment_intent.id,
        transaction_id: transaction.id,
        transaction_kind: transaction.kind,
        transaction_status: transaction.status,
        amount_cents: transaction.amount_cents,
        currency: payment_intent.currency,
        processor_ref: transaction.processor_ref,
        failure_code: transaction.failure_code,
        failure_message: transaction.failure_message,
        created_at: transaction.created_at.iso8601
      }
    }

    ProcessorEventService.call(
      event_type: event_type,
      payload: payload.merge(merchant: payment_intent.merchant)
    )
  end
end
