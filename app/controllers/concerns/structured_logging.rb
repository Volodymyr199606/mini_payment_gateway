# frozen_string_literal: true

module StructuredLogging
  extend ActiveSupport::Concern

  included do
    around_action :log_request
  end

  private

  def log_request
    request_id = request.env['request_id'] || Thread.current[:request_id]
    start_time = Time.current

    log_info(
      event: 'request_started',
      method: request.method,
      path: request.path,
      merchant_id: current_merchant&.id,
      request_id: request_id
    )

    yield
  rescue StandardError => e
    log_error(
      event: 'request_error',
      error: e.class.name,
      message: e.message,
      merchant_id: current_merchant&.id,
      request_id: request_id
    )
    raise
  ensure
    duration = ((Time.current - start_time) * 1000).round(2)
    log_info(
      event: 'request_completed',
      method: request.method,
      path: request.path,
      status: response.status,
      duration_ms: duration,
      merchant_id: current_merchant&.id,
      request_id: request_id
    )
  end

  def log_info(attributes = {})
    Rails.logger.info(format_log_entry(attributes))
  end

  def log_error(attributes = {})
    Rails.logger.error(format_log_entry(attributes))
  end

  def format_log_entry(attributes)
    # Structured JSON logging
    attributes.merge(
      timestamp: Time.current.iso8601,
      service: 'mini_payment_gateway'
    ).to_json
  end

  def log_transaction_event(event_type, transaction:, payment_intent: nil)
    log_info(
      event: event_type,
      transaction_id: transaction.id,
      payment_intent_id: payment_intent&.id || transaction.payment_intent_id,
      merchant_id: transaction.merchant.id,
      transaction_kind: transaction.kind,
      transaction_status: transaction.status,
      amount_cents: transaction.amount_cents,
      request_id: request.env['request_id'] || Thread.current[:request_id]
    )
  end
end
