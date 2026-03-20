# frozen_string_literal: true

# Canonical, deterministic fingerprint for idempotent API mutations.
# Used to ensure an idempotency key is only replayed for the same logical request.
class IdempotencyFingerprint
  SCHEMA_VERSION = 1

  ENDPOINT_HANDLERS = {
    'create_payment_intent' => :create_payment_intent,
    'authorize' => :payment_intent_mutation,
    'capture' => :payment_intent_mutation,
    'void' => :payment_intent_mutation,
    'refund' => :refund
  }.freeze

  class << self
    # Full fingerprint stored on new IdempotencyRecord rows.
    def compute(merchant_id:, endpoint:, request_params:)
      envelope = canonical_envelope(merchant_id: merchant_id, endpoint: endpoint, request_params: request_params)
      Digest::SHA256.hexdigest(JSON.generate(envelope))
    end

    # Legacy: matches pre-hardening IdempotencyService (SHA256 of request_params.to_json).
    def legacy_compute(request_params)
      Digest::SHA256.hexdigest(request_params.to_json)
    end

    private

    def canonical_envelope(merchant_id:, endpoint:, request_params:)
      {
        'v' => SCHEMA_VERSION,
        'merchant_id' => merchant_id,
        'endpoint' => endpoint.to_s,
        'payload' => normalized_payload(endpoint.to_s, request_params)
      }
    end

    def normalized_payload(endpoint, request_params)
      handler = ENDPOINT_HANDLERS[endpoint] || :generic
      send(handler, request_params)
    end

    def create_payment_intent(request_params)
      p = stringify_keys(request_params).except('idempotency_key')
      {
        'customer_id' => normalize_optional_id(p['customer_id']),
        'payment_method_id' => normalize_optional_id(p['payment_method_id']),
        'amount_cents' => normalize_amount_cents(p['amount_cents']),
        'currency' => normalize_currency(p['currency']),
        'metadata' => normalize_metadata(p['metadata'])
      }
    end

    def payment_intent_mutation(request_params)
      p = stringify_keys(request_params).except('idempotency_key')
      {
        'payment_intent_id' => normalize_id!(p['payment_intent_id'], 'payment_intent_id')
      }
    end

    def refund(request_params)
      p = stringify_keys(request_params).except('idempotency_key')
      {
        'payment_intent_id' => normalize_id!(p['payment_intent_id'], 'payment_intent_id'),
        'amount_cents' => normalize_amount_cents!(p['amount_cents'], 'amount_cents')
      }
    end

    # Fallback for unknown endpoints: stable deep-sorted map (no raw body).
    def generic(request_params)
      deep_sort_jsonish(stringify_keys(request_params).except('idempotency_key'))
    end

    def stringify_keys(hash)
      return {} if hash.nil?
      hash.each_with_object({}) { |(k, v), acc| acc[k.to_s] = v }
    end

    def normalize_optional_id(value)
      return nil if value.nil? || value == ''
      value.to_i
    end

    def normalize_id!(value, name)
      raise ArgumentError, "missing #{name}" if value.nil? || value == ''
      value.to_i
    end

    def normalize_amount_cents(value)
      return nil if value.nil? || value == ''
      value.to_i
    end

    def normalize_amount_cents!(value, name)
      raise ArgumentError, "missing #{name}" if value.nil? || value == ''
      value.to_i
    end

    def normalize_currency(value)
      return nil if value.nil? || value == ''
      value.to_s.upcase
    end

    def normalize_metadata(value)
      return {} if value.nil?
      return {} unless value.is_a?(Hash)
      deep_sort_jsonish(stringify_keys(value))
    end

    def deep_sort_jsonish(obj)
      case obj
      when Hash
        obj.keys.sort.each_with_object({}) { |k, h| h[k] = deep_sort_jsonish(obj[k]) }
      when Array
        obj.map { |e| deep_sort_jsonish(e) }
      else
        obj
      end
    end
  end
end
