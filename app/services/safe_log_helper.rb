# frozen_string_literal: true

# Centralizes safe logging to prevent secret leakage.
# Never log raw exception messages, full request bodies/headers, or URLs with credentials.
module SafeLogHelper
  class << self
    # Returns a safe string for logging. Redacts URLs, credentials, and sensitive patterns.
    # In production, prefer logging only error_class; use sanitized message only when needed.
    def sanitize_exception_message(exception)
      return exception.class.name if exception.nil?

      msg = exception.message.to_s
      return exception.class.name if msg.blank?

      # Redact common secret patterns (case-insensitive)
      redacted = msg
        .gsub(/password[=:]\s*[^\s&"')\]]+/i, 'password=[REDACTED]')
        .gsub(/api_key[=:]\s*[^\s&"')\]]+/i, 'api_key=[REDACTED]')
        .gsub(/secret[=:]\s*[^\s&"')\]]+/i, 'secret=[REDACTED]')
        .gsub(/token[=:]\s*[^\s&"')\]]+/i, 'token=[REDACTED]')
        .gsub(/(?:mysql|postgres|postgresql):\/\/[^:]+:[^@]+@[^\s]+/i, '[REDACTED_URL]')
        .gsub(/:\/\/[^:]+:[^@]+@[^\s]+/, '[REDACTED_URL]')

      # Truncate to limit accidental leakage
      redacted = redacted[0, 200] + '...' if redacted.length > 200
      redacted.presence || exception.class.name
    end

    # Structured error log payload. Never includes raw exception message in production.
    def safe_error_payload(event:, error_class: nil, exception: nil, **metadata)
      payload = {
        timestamp: Time.current.iso8601,
        service: 'mini_payment_gateway',
        event: event,
        error_class: error_class || (exception && exception.class.name)
      }.merge(metadata)

      # Only include sanitized message in development; in production log error_class only
      if exception && Rails.env.development?
        payload[:message] = sanitize_exception_message(exception)
      end

      payload.to_json
    end
  end
end
