# frozen_string_literal: true

module Ai
  module Agents
    class BaseAgent
      # Minimum context length (chars) to consider calling the LLM; below this we return a deterministic fallback.
      LOW_CONTEXT_THRESHOLD = 80
      MAX_MEMORY_CHARS = 2000

      SYSTEM_RULES = <<~TEXT
        You are a read-only assistant for a payment gateway. Use ONLY the provided Context sections to answer.

        ## Style (strict)
        - Write directly. Never use meta phrases like "According to the provided context", "Based on the context", "We can infer", "The context states".
        - Answer must be supported by retrieved Context. Do NOT invent or guess.
        - Do NOT put citation references inside the prose (no [docs/...], no inline file paths). Citations are passed separately; your reply text must be clean.

        ## When the answer is NOT in the provided context (strict)
        - Respond with exactly: "Not found in docs yet."
        - Then suggest exactly ONE specific docs/*.md file to add or update, and exactly ONE section title to add (e.g. "Add docs/REFUNDS.md with section 'Refund time limits'").
        - Then ask exactly ONE clarifying question if it would help (e.g. time range, which product). If not needed, omit.

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

      def initialize(merchant_context: nil, message:, context_text:, citations: [], conversation_history: [], memory_text: '')
        @merchant_context = merchant_context
        @message = message.to_s
        @context_text = context_text
        @citations = citations
        @conversation_history = conversation_history.to_a
        @memory_text = memory_text.to_s.strip
      end

      def call
        if detect_low_context?(@context_text)
          return {
            reply: low_context_fallback_message,
            citations: @citations,
            model_used: nil,
            fallback_used: true
          }
        end

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

      # True when context is empty or too small to answer from; agent should return deterministic fallback without calling LLM.
      def detect_low_context?(context_text)
        return true if context_text.blank?
        context_text.to_s.length < LOW_CONTEXT_THRESHOLD
      end

      # Deterministic message when context is too low (no LLM call).
      def low_context_fallback_message
        "I don't have enough docs context to answer this yet. Try asking about a documented topic (e.g. refunds, authorize vs capture) or add a doc section for your question in docs/."
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
        system_content = system_instructions

        # Memory (summary + recent messages) before RAG context; capped to keep token budget sane.
        if @memory_text.present?
          memory_block = @memory_text.length > MAX_MEMORY_CHARS ? @memory_text.truncate(MAX_MEMORY_CHARS) : @memory_text
          system_content += "\n\nMemory:\n#{memory_block}"
        end

        system_content += "\n\nContext (use only this):\n#{@context_text || 'No context retrieved.'}"
        user_content = @message
        user_content += "\n\n[Context ends. Answer using only the context above. Do NOT embed citation strings in your reply; citations are passed separately.]" if @context_text.present?

        # When memory is present, recent messages are in Memory; otherwise use conversation_history.
        messages = [{ role: 'system', content: system_content }]
        @conversation_history.each { |h| messages << { role: h[:role].to_s, content: h[:content].to_s } } if @memory_text.blank?
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
