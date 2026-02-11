# frozen_string_literal: true

class BaseService
  attr_reader :result, :errors

  def self.call(*, **)
    new(*, **).call
  end

  def initialize(*_args, **_kwargs)
    @errors = []
    @result = nil
  end

  def call
    raise NotImplementedError, 'Subclasses must implement #call'
  end

  def success?
    @errors.empty?
  end

  def failure?
    !success?
  end

  protected

  def add_error(message)
    @errors << message
  end

  def set_result(value)
    @result = value
  end

  def processor_timeout_seconds
    ENV.fetch('PROCESSOR_TIMEOUT_SECONDS', '3').to_i
  end

  def log_processor_timeout(merchant_id:, payment_intent_id:, transaction_id:, kind:, timeout_seconds:)
    Rails.logger.info(
      {
        timestamp: Time.current.iso8601,
        service: 'mini_payment_gateway',
        event: 'processor_timeout',
        request_id: Thread.current[:request_id],
        merchant_id: merchant_id,
        payment_intent_id: payment_intent_id,
        transaction_id: transaction_id,
        transaction_kind: kind,
        timeout_seconds: timeout_seconds
      }.to_json
    )
  end
end
