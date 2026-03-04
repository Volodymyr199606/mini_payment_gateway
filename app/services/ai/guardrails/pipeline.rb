# frozen_string_literal: true

module Ai
  module Guardrails
    # Runs guard steps in order. May short-circuit (empty retrieval) or trigger one re-ask (citation).
    # input:  { built_messages: [...] }
    # result: nil (before LLM) or { content:, model_used:, fallback_used: }
    # context: { context_text:, citations: }
    # llm_call: optional Proc (messages) -> { content:, model_used:, fallback_used: }
    # Returns: { short_circuit:, reply_text:, model_used:, fallback_used:, guardrail_reask:, secret_leak_detected: }
    class Pipeline
      STEPS = [
        EmptyRetrievalGuard,
        CitationEnforcementGuard,
        SecretLeakGuard
      ].freeze

      def self.call(input:, result:, context:, llm_call: nil)
        state = normalize_result(result)

        STEPS.each do |step|
          out = step.apply(input: input, result: state, context: context, llm_call: llm_call)
          return out if out[:short_circuit]

          state = out
        end

        finalize(state)
      end

      def self.normalize_result(result)
        return {} if result.nil?
        return result if result[:short_circuit]

        {
          content: result[:content].to_s.strip,
          model_used: result[:model_used],
          fallback_used: result[:fallback_used],
          reply_text: result[:reply_text] || result[:content].to_s.strip,
          guardrail_reask: result[:guardrail_reask] || false,
          secret_leak_detected: result[:secret_leak_detected] || false
        }
      end

      def self.finalize(state)
        {
          short_circuit: false,
          reply_text: state[:reply_text].to_s,
          model_used: state[:model_used],
          fallback_used: state[:fallback_used],
          guardrail_reask: state[:guardrail_reask] || false,
          secret_leak_detected: state[:secret_leak_detected] || false
        }
      end
    end
  end
end
