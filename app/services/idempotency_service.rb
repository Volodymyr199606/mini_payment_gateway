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

    fingerprint_canonical = IdempotencyFingerprint.compute(
      merchant_id: @merchant.id,
      endpoint: @endpoint.to_s,
      request_params: @request_params
    )
    fingerprint_legacy = IdempotencyFingerprint.legacy_compute(@request_params)

    existing_record = IdempotencyRecord.find_by(
      merchant: @merchant,
      idempotency_key: @idempotency_key,
      endpoint: @endpoint.to_s
    )

    if existing_record
      unless fingerprints_match?(existing_record.request_hash, fingerprint_canonical, fingerprint_legacy)
        log_idempotency_mismatch!
        set_result(
          conflict: true,
          cached: false,
          fingerprint_mismatch: true,
          status_code: 409,
          response_body: nil
        )
        return self
      end

      set_result({
                   cached: true,
                   response_body: existing_record.response_body,
                   status_code: existing_record.status_code
                 })
      return self
    end

    # Placeholder row updated after successful operation; { pending: true } satisfies presence validation.
    @idempotency_record = IdempotencyRecord.new(
      merchant: @merchant,
      idempotency_key: @idempotency_key,
      endpoint: @endpoint.to_s,
      request_hash: fingerprint_canonical,
      response_body: { pending: true },
      status_code: 200
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

  private

  # Canonical fingerprint (v1) or legacy SHA256(request_params.to_json) for rows created before hardening.
  def fingerprints_match?(stored, canonical, legacy)
    secure_hex_equal?(stored, canonical) || secure_hex_equal?(stored, legacy)
  end

  def secure_hex_equal?(a, b)
    return false unless a.is_a?(String) && b.is_a?(String)
    return false unless a.bytesize == b.bytesize

    ActiveSupport::SecurityUtils.secure_compare(a, b)
  end

  def log_idempotency_mismatch!
    payload = {
      timestamp: Time.current.iso8601,
      service: 'mini_payment_gateway',
      event: 'idempotency_mismatch',
      merchant_id: @merchant.id,
      endpoint: @endpoint.to_s,
      idempotency_key: @idempotency_key,
      mismatch_detected: true,
      request_hash_mismatch: true,
      request_id: Thread.current[:request_id]
    }
    Rails.logger.warn(payload.to_json)

    AuditLogService.call(
      merchant: @merchant,
      action: 'idempotency_mismatch',
      actor_type: 'system',
      actor_id: 'idempotency',
      metadata: {
        endpoint: @endpoint.to_s,
        idempotency_key: @idempotency_key,
        mismatch_detected: true,
        request_hash_mismatch: true,
        request_id: Thread.current[:request_id]
      }
    )
  end
end
