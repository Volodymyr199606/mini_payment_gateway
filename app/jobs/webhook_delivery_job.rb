# frozen_string_literal: true

class WebhookDeliveryJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(webhook_event_id)
    webhook_event = WebhookEvent.find(webhook_event_id)

    # Skip if already delivered or failed
    return if webhook_event.delivery_status != 'pending'

    service = WebhookDeliveryService.call(webhook_event: webhook_event)

    return if service.success?

    Rails.logger.error("Webhook delivery failed: #{service.errors.join(', ')}")
  end
end
