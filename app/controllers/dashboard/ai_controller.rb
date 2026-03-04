# frozen_string_literal: true

module Dashboard
  class AiController < Dashboard::BaseController
    AI_RATE_LIMIT = 20
    AI_RATE_WINDOW = 60

    def show
      # Renders the AI chat page
    end

    def reset_chat_session
      current_merchant.ai_chat_sessions.create!
      render json: { ok: true }
    end

    def chat
      msg = parse_message_param.to_s.strip
      if msg.blank?
        return render json: { error: 'message_required', message: 'Message is required' }, status: :bad_request
      end

      if ai_rate_limited?
        return render json: {
          error: 'rate_limited',
          message: "AI chat limit: #{AI_RATE_LIMIT} requests per #{AI_RATE_WINDOW} seconds."
        }, status: :too_many_requests
      end

      chat_session = find_or_create_chat_session
      AiChatMessage.create!(
        ai_chat_session: chat_session,
        merchant_id: current_merchant.id,
        role: 'user',
        content: msg
      )

      ctx = ::Ai::ConversationContextBuilder.call(chat_session, max_turns: 8)
      memory_text = ctx[:memory_text].to_s
      conversation_history = memory_text.present? ? [] : chat_session.ai_chat_messages.chronological.limit(10).map { |m| { role: m.role, content: m.content } }[0..-2] || []

      agent_param = chat_params[:agent].to_s.strip
      agent_key = if agent_param.present? && agent_param != "auto"
                    agent_param.to_sym
                  else
                    ::Ai::Router.new(msg).call
                  end
      retriever_result = ::Ai::Rag::RetrievalService.call(msg, agent_key: agent_key)
      context_text = retriever_result[:context_text]
      citations = retriever_result[:citations]

      agent_class = agent_class_for(agent_key)
      agent = build_agent(agent_class, agent_key, msg, context_text, citations, conversation_history: conversation_history, memory_text: memory_text)

      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      out = agent.call
      latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round

      AiChatMessage.create!(
        ai_chat_session: chat_session,
        merchant_id: current_merchant.id,
        role: 'assistant',
        content: out[:reply],
        agent: agent_key.to_s
      )

      increment_ai_chat_count

      payload = {
        reply: out[:reply],
        agent: agent_key.to_s,
        citations: out[:citations],
        model_used: out[:model_used],
        fallback_used: out[:fallback_used]
      }
      payload[:data] = out[:data] if out[:data].present?

      render json: payload
    end

    private

    def chat_params
      params.permit(:message, :agent)
    end

    # Accept JSON body { message: "..." } or form-encoded message param.
    def parse_message_param
      return chat_params[:message] if params.key?(:message) || params.key?("message")
      return nil unless request.content_type.to_s.include?("application/json")

      parsed = JSON.parse(request.raw_post)
      parsed["message"] || parsed[:message]
    rescue JSON::ParserError
      nil
    end

    def build_agent(agent_class, agent_key, message, context_text, citations, conversation_history: [], memory_text: '')
      if agent_key == :reporting_calculation
        agent_class.new(merchant_id: current_merchant.id, message: message, context_text: context_text, citations: citations)
      else
        agent_class.new(
          message: message,
          context_text: context_text,
          citations: citations,
          conversation_history: conversation_history,
          memory_text: memory_text
        )
      end
    end

    def agent_class_for(key)
      case key
      when :support_faq then ::Ai::Agents::SupportFaqAgent
      when :security_compliance then ::Ai::Agents::SecurityAgent
      when :developer_onboarding then ::Ai::Agents::OnboardingAgent
      when :operational then ::Ai::Agents::OperationalAgent
      when :reconciliation_analyst then ::Ai::Agents::ReconciliationAgent
      when :reporting_calculation then ::Ai::Agents::ReportingCalculationAgent
      else ::Ai::Agents::SupportFaqAgent
      end
    end

    def ai_rate_limited?
      key = "ai_chat:merchant:#{current_merchant.id}"
      count = (Rails.cache.read(key) || 0).to_i
      count >= AI_RATE_LIMIT
    end

    def increment_ai_chat_count
      key = "ai_chat:merchant:#{current_merchant.id}"
      count = (Rails.cache.read(key) || 0).to_i
      Rails.cache.write(key, count + 1, expires_in: AI_RATE_WINDOW.seconds)
    end

    # Find the most recent chat session for the current merchant, or create one (scoped to merchant).
    def find_or_create_chat_session
      current_merchant.ai_chat_sessions.order(updated_at: :desc).first ||
        current_merchant.ai_chat_sessions.create!
    end
  end
end
