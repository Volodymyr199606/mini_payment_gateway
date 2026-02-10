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

    # Queue delivery job
    WebhookDeliveryJob.perform_later(webhook_event.id)

    set_result(webhook_event)
    self
  rescue StandardError => e
    add_error("Failed to create processor event: #{e.message}")
    self
  end

  private

  def webhook_secret
    Rails.application.config.webhook_secret
  end
end
