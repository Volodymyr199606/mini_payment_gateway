# frozen_string_literal: true

class ProcessorEventService < BaseService
  EVENT_TYPES = %w[
    transaction.succeeded
    transaction.failed
    chargeback.opened
  ].freeze

  def initialize(event_type:, payload: {})
    super()
    @event_type = event_type
    @payload = payload
  end

  def call
    unless EVENT_TYPES.include?(@event_type)
      add_error("Invalid event type: #{@event_type}")
      return self
    end

    # Create webhook event
    webhook_event = WebhookEvent.create!(
      merchant: @payload[:merchant],
      event_type: @event_type,
      payload: @payload,
      delivery_status: 'pending'
    )

    # Generate signature
    payload_json = @payload.to_json
    signature = WebhookSignatureService.generate_signature(
      payload_json,
      webhook_secret
    )

    webhook_event.update!(signature: signature)

    # Job is enqueued via WebhookEvent#after_commit to ensure delivery happens only after DB commit

    set_result(webhook_event)
    self
  rescue StandardError => e
    add_error('processor_event_creation_failed')
    self
  end

  private

  def webhook_secret
    Rails.application.config.webhook_secret
  end
end
