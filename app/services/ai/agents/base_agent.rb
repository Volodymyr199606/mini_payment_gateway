# frozen_string_literal: true

module Ai
  module Agents
    class BaseAgent
      # Minimum context length (chars) to consider calling the LLM; below this we return a deterministic fallback.
      LOW_CONTEXT_THRESHOLD = 80

      # Shown when retriever returns no sections; suggests where to look next.
      EMPTY_RETRIEVAL_FALLBACK = "I couldn't find this in the docs. Here's what I can say generally: " \
        "check the Dashboard for live data, the API reference for endpoints, and the docs in this app for " \
        "payment lifecycle, refunds, and security. Try asking about a specific topic (e.g. refunds, authorize vs capture) " \
        "or rephrase your question."
      WHERE_TO_LOOK_SUGGESTIONS = [
        'Dashboard (payments, refunds)',
        'docs/PAYMENT_LIFECYCLE.md',
        'docs/REFUNDS_API.md',
        'docs/ARCHITECTURE.md',
        'docs/SECURITY.md'
      ].freeze

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

      def initialize(merchant_context: nil, message:, context_text:, citations: [], conversation_history: [], memory_text: '', response_style: nil)
        @merchant_context = merchant_context
        @message = message.to_s
        @context_text = context_text
        @citations = citations
        @conversation_history = conversation_history.to_a
        @memory_text = memory_text.to_s.strip
        @response_style = Array(response_style).compact
      end

      def call
        messages = build_messages
        pipeline_context = { context_text: @context_text, citations: @citations }

        # Pre-LLM: empty retrieval guard may short-circuit and skip LLM
        pre = ::Ai::Guardrails::Pipeline.call(
          input: { built_messages: messages },
          result: nil,
          context: pipeline_context
        )
        return build_result_from_pipeline(pre) if pre[:short_circuit]

        # Single LLM call
        raw = groq_client.chat(messages: messages, temperature: 0.3, max_tokens: 1024)
        content = raw[:content].to_s.strip
        content = "I couldn't generate a reply." if content.blank? && raw[:error].present?
        if content.blank?
          ::Ai::Observability::EventLogger.log_guardrail(
            event: 'safe_fallback',
            request_id: Thread.current[:ai_request_id],
            citations_count: @citations.size,
            context_length: @context_text.to_s.length
          )
          content = fallback_message
        end
        content = strip_inline_citations(strip_filler_phrases(content))

        llm_call = build_llm_call_for_pipeline

        # Post-LLM: citation enforcement (may re-ask once) and secret leak guard
        post = ::Ai::Guardrails::Pipeline.call(
          input: { built_messages: messages },
          result: { content: content, model_used: raw[:model_used], fallback_used: raw[:fallback_used] },
          context: pipeline_context,
          llm_call: llm_call
        )

        build_result_from_pipeline(post)
      end

      # True when context is empty or too small to answer from; agent should return deterministic fallback without calling LLM.
      def detect_low_context?(context_text)
        return true if context_text.blank?
        context_text.to_s.length < LOW_CONTEXT_THRESHOLD
      end

      # Deterministic message when context is too low or retriever returned no sections (no LLM call).
      def low_context_fallback_message
        suggestions = WHERE_TO_LOOK_SUGGESTIONS.map { |s| "• #{s}" }.join("\n")
        "#{EMPTY_RETRIEVAL_FALLBACK}\n\nWhere to look next:\n#{suggestions}"
      end

      def agent_name
        self.class.name.demodulize.underscore.sub(/_agent$/, '')
      end

      # Messages for LLM; used by streaming path. Subclasses inherit build_messages.
      def messages_for_llm
        build_messages
      end

      # Build AgentResult for consistent contract. Subclasses may override or call with extra options.
      def build_result(reply_text:, model_used: nil, fallback_used: false, guardrail_reask: false, data: nil)
        ::Ai::AgentResult.new(
          reply_text: reply_text,
          citations: @citations,
          agent_key: agent_name,
          model_used: model_used,
          fallback_used: fallback_used,
          metadata: {
            docs_used_count: @citations.size,
            summary_used: @memory_text.present?,
            guardrail_reask: guardrail_reask
          },
          data: data
        )
      end

      def build_result_from_pipeline(pipeline_out)
        build_result(
          reply_text: pipeline_out[:reply_text].to_s,
          model_used: pipeline_out[:model_used],
          fallback_used: pipeline_out[:fallback_used],
          guardrail_reask: pipeline_out[:guardrail_reask] || false
        )
      end

      def build_llm_call_for_pipeline
        ->(messages) {
          r = groq_client.chat(messages: messages, temperature: 0.3, max_tokens: 1024)
          content = r[:content].to_s.strip
          content = strip_inline_citations(strip_filler_phrases(content)) if content.present?
          { content: content, model_used: r[:model_used], fallback_used: r[:fallback_used] }
        }
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

        # Memory (summary + recent messages) before RAG context; already budgeted by MemoryBudgeter when present.
        if @memory_text.present?
          system_content += "\n\nMemory:\n#{@memory_text}"
        end

        system_content += response_style_hint if @response_style.any?
        system_content += "\n\nContext (use only this):\n#{@context_text || 'No context retrieved.'}"
        user_content = @message
        user_content += "\n\n[Context ends. Answer using only the context above. Do NOT embed citation strings in your reply; citations are passed separately.]" if @context_text.present?

        # When memory is present, recent messages are in Memory; otherwise use conversation_history.
        messages = [{ role: 'system', content: system_content }]
        @conversation_history.each { |h| messages << { role: h[:role].to_s, content: h[:content].to_s } } if @memory_text.blank?
        messages << { role: 'user', content: user_content }
        messages
      end

      def response_style_hint
        return '' if @response_style.empty?

        hints = @response_style.map do |s|
          case s.to_sym
          when :simpler then 'use simpler language'
          when :shorter then 'be brief and concise'
          when :more_detailed then 'include more detail'
          when :more_technical then 'use more technical terms'
          when :bullet_points then 'use bullet points'
          when :only_important then 'focus only on the most important points'
          else s.to_s
          end
        end
        "\n\nResponse style (user request): #{hints.join('; ')}."
      end

      def fallback_message
        "Not found in docs yet. Consider adding or updating a doc in docs/ with a section for this topic."
      end

      # True if reply text references at least one citation by file path or doc name (not just heading word).
      def reply_references_citations?(reply, citations)
        return false if reply.blank? || citations.blank?
        normalized = reply.to_s.downcase
        citations.any? do |c|
          file = c[:file].to_s
          base = File.basename(file, '.*')
          normalized.include?(file.downcase) || normalized.include?(base.downcase)
        end
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
