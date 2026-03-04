# frozen_string_literal: true

module Ai
  module Guardrails
    # Redact sensitive patterns from reply and prepend a warning if any were found.
    class SecretLeakGuard
      WARNING_PREFIX = "[Response was partially redacted because it contained sensitive-looking content.]\n\n"

      def self.apply(input:, result:, context:, llm_call: nil)
        return result if result.nil? || result[:short_circuit]

        text = (result[:reply_text] || result[:content]).to_s
        return result if text.blank?

        redacted = Ai::MessageSanitizer.sanitize(text)
        return result if redacted == text

        reply_text = WARNING_PREFIX + redacted
        result.merge(reply_text: reply_text, secret_leak_detected: true)
      end
    end
  end
end
