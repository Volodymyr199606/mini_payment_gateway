# frozen_string_literal: true

module Ai
  module Guardrails
    # Short-circuit: skip LLM and return fallback when retrieval is empty or too small.
    class EmptyRetrievalGuard
      LOW_CONTEXT_THRESHOLD = 80

      FALLBACK_MESSAGE = "I couldn't find this in the docs. Here's what I can say generally: " \
        "check the Dashboard for live data, the API reference for endpoints, and the docs in this app for " \
        "payment lifecycle, refunds, and security. Try asking about a specific topic (e.g. refunds, authorize vs capture) " \
        "or rephrase your question."
      WHERE_TO_LOOK = [
        'Dashboard (payments, refunds)',
        'docs/PAYMENT_LIFECYCLE.md',
        'docs/REFUNDS_API.md',
        'docs/ARCHITECTURE.md',
        'docs/SECURITY.md'
      ].freeze

      def self.apply(input:, result:, context:, llm_call: nil)
        if result.present? && result[:content].to_s.present?
          return result
        end

        context_text = context[:context_text].to_s
        if context_text.length >= LOW_CONTEXT_THRESHOLD
          return result || {}
        end

        reply_text = FALLBACK_MESSAGE + "\n\nWhere to look next:\n" +
          WHERE_TO_LOOK.map { |s| "• #{s}" }.join("\n")

        ::Ai::Observability::EventLogger.log_guardrail(
          event: 'empty_retrieval_fallback',
          request_id: Thread.current[:ai_request_id],
          citations_count: context[:citations].to_a.size,
          context_length: context_text.length
        )

        {
          short_circuit: true,
          reply_text: reply_text,
          model_used: nil,
          fallback_used: true,
          guardrail_reask: false,
          secret_leak_detected: false
        }
      end
    end
  end
end
