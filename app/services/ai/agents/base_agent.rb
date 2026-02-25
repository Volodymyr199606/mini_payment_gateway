# frozen_string_literal: true

module Ai
  module Agents
    class BaseAgent
      SYSTEM_RULES = <<~TEXT
        You are a read-only assistant for a payment gateway. Use ONLY the provided Context sections to answer.
        Include citations by referencing the section (file and heading). If the Context does not contain the answer, say so and suggest which doc to add or update.
        Do not instruct users to run real payment actions (authorize, capture, refund, void) or to store card numbers (PAN). You only explain and guide.
      TEXT

      def initialize(merchant_context: nil, message:, context_text:, citations: [])
        @merchant_context = merchant_context
        @message = message.to_s
        @context_text = context_text
        @citations = citations
      end

      def call
        messages = build_messages
        result = groq_client.chat(messages: messages, temperature: 0.3, max_tokens: 1024)
        content = result[:content].to_s.strip
        content = "I couldn't generate a reply." if content.blank? && result[:error].present?
        content = fallback_message if content.blank?
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
        user_content += "\n\n[Context ends. Answer using only the context above and cite file/heading.]" if @context_text.present?

        [
          { role: 'system', content: system_content },
          { role: 'user', content: user_content }
        ]
      end

      def fallback_message
        "I don't have enough information in the docs to answer that. Consider adding or updating a doc (e.g. in docs/) and try again."
      end
    end
  end
end
