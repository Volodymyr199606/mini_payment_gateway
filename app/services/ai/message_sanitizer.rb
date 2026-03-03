# frozen_string_literal: true

module Ai
  # Redacts likely secrets from text before sending to LLM or storing in summaries.
  # Regex-based; does not persist or log raw values.
  class MessageSanitizer
    REDACT_PLACEHOLDER = '[REDACTED]'

    # Common patterns: API key prefixes, long hex/token-like strings, param values
    PATTERNS = [
      /\b(?:api[_-]?key|apikey)\s*[:=]\s*['"]?[\w-]{20,}['"]?/i,
      /\b(?:bearer)\s+[\w.-]{20,}/i,
      /\bsk[-_][a-zA-Z0-9]{20,}\b/,           # Stripe-style
      /\b[a-f0-9]{32,}\b/i,                    # long hex (e.g. API key hashes)
      /\b(?:token|secret|password)\s*[:=]\s*['"]?[^\s'"]{12,}['"]?/i
    ].freeze

    def self.sanitize(text)
      return '' if text.blank?

      result = text.to_s.dup
      PATTERNS.each { |re| result.gsub!(re, REDACT_PLACEHOLDER) }
      result
    end
  end
end
