# frozen_string_literal: true

module Ai
  module Guardrails
    # Re-ask LLM once with "Answer again and cite sources." if reply does not reference any citation.
    class CitationEnforcementGuard
      REASK_PROMPT = 'Answer again and cite sources.'

      def self.apply(input:, result:, context:, llm_call: nil)
        return result if result.nil? || result[:short_circuit]
        return result if context[:citations].to_a.empty?
        return result unless llm_call.respond_to?(:call)

        content = result[:content].to_s.strip
        return result if content.blank?
        return result if reply_references_citations?(content, context[:citations])

        messages = input[:built_messages].to_a
        return result if messages.empty?

        retry_messages = messages + [
          { role: 'assistant', content: content },
          { role: 'user', content: REASK_PROMPT }
        ]
        retry_result = llm_call.call(retry_messages)
        retry_content = retry_result[:content].to_s.strip

        next_content = retry_content.present? ? retry_content : content
        next_model = retry_content.present? ? retry_result[:model_used] : result[:model_used]
        next_fallback = retry_content.present? ? retry_result[:fallback_used] : result[:fallback_used]

        ::Ai::Observability::EventLogger.log_guardrail(
          event: 'citation_reask',
          request_id: Thread.current[:ai_request_id],
          citations_count: context[:citations].to_a.size,
          context_length: context[:context_text].to_s.length
        )

        result.merge(
          content: next_content,
          reply_text: next_content,
          model_used: next_model,
          fallback_used: next_fallback,
          guardrail_reask: true
        )
      end

      def self.reply_references_citations?(reply, citations)
        return false if reply.blank? || citations.blank?
        normalized = reply.downcase
        citations.any? do |c|
          file = (c[:file] || c['file']).to_s
          base = File.basename(file, '.*')
          normalized.include?(file.downcase) || normalized.include?(base.downcase)
        end
      end
    end
  end
end
