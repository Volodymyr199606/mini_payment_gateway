# frozen_string_literal: true

class IdempotencyService < BaseService
  def initialize(merchant:, idempotency_key:, endpoint:, request_params: {})
    super()
    @merchant = merchant
    @idempotency_key = idempotency_key
    @endpoint = endpoint
    @request_params = request_params
  end

  def call
    return self unless @idempotency_key.present?

    request_hash = Digest::SHA256.hexdigest(@request_params.to_json)

    existing_record = IdempotencyRecord.find_by(
      merchant: @merchant,
      idempotency_key: @idempotency_key,
      endpoint: @endpoint
    )

    if existing_record
      # Return cached response
      set_result({
                   cached: true,
                   response_body: existing_record.response_body,
                   status_code: existing_record.status_code
                 })
      return self
    end

    # Store idempotency record placeholder (will be updated after successful operation)
    # Use non-blank response_body so presence validation passes; { pending: true } is non-blank
    @idempotency_record = IdempotencyRecord.new(
      merchant: @merchant,
      idempotency_key: @idempotency_key,
      endpoint: @endpoint,
      request_hash: request_hash,
      response_body: { pending: true },
      status_code: 200 # Placeholder
    )
    @idempotency_record.save!

    set_result({ cached: false, idempotency_record: @idempotency_record })
    self
  end

  def store_response(response_body:, status_code:)
    return unless @idempotency_record

    @idempotency_record.update!(
      response_body: response_body,
      status_code: status_code
    )
  end
end
