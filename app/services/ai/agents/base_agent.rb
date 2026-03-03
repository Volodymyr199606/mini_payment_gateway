# frozen_string_literal: true

module Ai
  module Agents
    class BaseAgent
      SYSTEM_RULES = <<~TEXT
        You are a read-only assistant for a payment gateway. Use ONLY the provided Context sections to answer.

        ## Style (strict)
        - Write directly. Never use meta phrases like "According to the provided context", "Based on the context", "We can infer", "The context states".
        - Answer must be supported by retrieved Context OR explicitly say: "Not found in docs yet."
        - If not found: suggest exactly ONE doc file to add/update and the section name to add.
        - Do NOT put citation references inside the prose (no [docs/...], no inline file paths). Citations are passed separately; your reply text must be clean.

        ## Output format
        - 1–2 sentence direct answer first
        - Then 2–6 bullets with key details
        - No inline citation strings in the reply body

        ## Ambiguity
        - If the question is ambiguous (e.g. time range, definition scope), ask exactly ONE clarifying question.

        ## Numbers
        - Never invent numbers. For totals, fees, or "how much" questions, the reporting tool provides the data—you must not calculate or guess.

        ## Safety
        - Do not instruct users to run real payment actions (authorize, capture, refund, void) or to store card numbers (PAN). You only explain and guide.
      TEXT

      def initialize(merchant_context: nil, message:, context_text:, citations: [], conversation_history: [])
        @merchant_context = merchant_context
        @message = message.to_s
        @context_text = context_text
        @citations = citations
        @conversation_history = conversation_history.to_a
      end

      def call
        messages = build_messages
        result = groq_client.chat(messages: messages, temperature: 0.3, max_tokens: 1024)
        content = result[:content].to_s.strip
        content = "I couldn't generate a reply." if content.blank? && result[:error].present?
        content = fallback_message if content.blank?
        content = strip_inline_citations(strip_filler_phrases(content))
        {
          reply: content,
          citations: @citations,
          model_used: result[:model_used],
          fallback_used: result[:fallback_used]
        }
      end

      def agent_name
        self.class.name.demodulize.underscore.sub(/_agent$/, '')
      end

      protected

      def system_instructions
        SYSTEM_RULES
      end

      def groq_client
        @groq_client ||= Ai::GroqClient.new
      end

      def build_messages
        system_content = system_instructions + "\n\nContext (use only this):\n#{@context_text || 'No context retrieved.'}"
        user_content = @message
        user_content += "\n\n[Context ends. Answer using only the context above. Do NOT embed citation strings in your reply; citations are passed separately.]" if @context_text.present?

        messages = [{ role: 'system', content: system_content }]
        @conversation_history.each do |h|
          messages << { role: h[:role].to_s, content: h[:content].to_s }
        end
        messages << { role: 'user', content: user_content }
        messages
      end

      def fallback_message
        "Not found in docs yet. Consider adding or updating a doc in docs/ with a section for this topic."
      end

      # Remove any inline citation refs the model might have added
      def strip_inline_citations(text)
        return text if text.blank?
        text.gsub(/\s*\[docs?\/[^\]]*\]\s*/i, " ").gsub(/\s*\(docs?\/[^)]*\)\s*/i, " ").squeeze(" ").strip
      end

      # Remove filler/meta phrases the model might have added despite prompt
      FILLER_PATTERNS = [
        /\bAccording to (?:the )?(?:provided )?context[,:]?\s*/i,
        /\bBased on (?:the )?(?:provided )?context[,:]?\s*/i,
        /\bWe can infer (?:that )?/i,
        /\bThe context states?\s*/i,
        /\bFrom the (?:provided )?context[,:]?\s*/i
      ].freeze

      def strip_filler_phrases(text)
        return text if text.blank?
        result = text.dup
        FILLER_PATTERNS.each { |re| result.gsub!(re, "") }
        result.squeeze(" ").strip
      end
    end
  end
end
