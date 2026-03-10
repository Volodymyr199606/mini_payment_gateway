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

      Thread.current[:ai_request_id] = request.request_id
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      retriever_result = nil
      out = nil
      agent_key = nil
      selected_retriever = nil
      memory_text = nil
      recent_count = 0

      chat_session = find_or_create_chat_session
      AiChatMessage.create!(
        ai_chat_session: chat_session,
        merchant_id: current_merchant.id,
        role: 'user',
        content: msg
      )

      ctx = ::Ai::ConversationContextBuilder.call(chat_session, max_turns: ::Ai::Conversation::MemoryBudgeter.max_recent_messages)
      memory_result = ::Ai::Conversation::MemoryBudgeter.call(
        summary_text: ctx[:summary_text],
        recent_messages: ctx[:recent_messages],
        user_preferences: ctx[:user_preferences],
        open_tasks_or_followups: ctx[:open_tasks_or_followups],
        current_topic: ctx[:current_topic],
        sanitization_applied: ctx[:summary_text].present?
      )
      memory_text = memory_result[:memory_text].to_s
      conversation_history = memory_text.present? ? [] : chat_session.ai_chat_messages.chronological.limit(10).map { |m| { role: m.role, content: m.content } }[0..-2] || []
      recent_count = memory_result[:recent_messages_count]

      agent_param = chat_params[:agent].to_s.strip
      agent_key = if agent_param.present? && agent_param != "auto"
                    agent_param.to_sym
                  else
                    ::Ai::Router.new(msg).call
                  end
      agent_key = ::Ai::AgentRegistry.default_key unless ::Ai::AgentRegistry.all_keys.include?(agent_key)
      retriever_result = ::Ai::Rag::RetrievalService.call(msg, agent_key: agent_key)
      selected_retriever = retriever_result.dig(:debug, :retriever).presence || resolve_retriever_name
      context_text = retriever_result[:context_text]
      citations = retriever_result[:citations]

      agent_class = ::Ai::AgentRegistry.fetch(agent_key)
      agent = build_agent(agent_class, agent_key, msg, context_text, citations, conversation_history: conversation_history, memory_text: memory_text)

      out = agent.call
      latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round

      AiChatMessage.create!(
        ai_chat_session: chat_session,
        merchant_id: current_merchant.id,
        role: 'assistant',
        content: out.reply_text,
        agent: out.agent_key
      )

      increment_ai_chat_count

      log_ai_request_success(out, msg, agent_key, retriever_result, selected_retriever, latency_ms, memory_result, recent_count)

      payload = {
        reply: out.reply_text,
        agent: out.agent_key,
        citations: out.citations,
        model_used: out.model_used,
        fallback_used: out.fallback_used
      }
      payload[:data] = out.data if out.data.present?
      payload[:debug] = build_debug_payload(out, agent_key, selected_retriever, retriever_result, latency_ms, memory_result) if ai_debug?

      render json: payload
    rescue StandardError => e
      latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
      log_ai_request_error(e, msg, agent_key, retriever_result, selected_retriever, latency_ms)
      raise
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

    def ai_debug?
      ::Ai::Observability::EventLogger.ai_debug_enabled?
    end

    def resolve_retriever_name
      graph = ENV['AI_CONTEXT_GRAPH_ENABLED'].to_s.strip.downcase.in?(%w[true 1])
      vector = ENV['AI_VECTOR_RAG_ENABLED'].to_s.strip.downcase.in?(%w[true 1])
      graph ? 'GraphExpandedRetriever' : (vector ? 'HybridRetriever' : 'DocsRetriever')
    end

    def log_ai_request_success(out, msg, agent_key, retriever_result, selected_retriever, latency_ms, memory_result, recent_count)
      ::Ai::Observability::EventLogger.log_ai_request(
        request_id: request.request_id,
        endpoint: 'dashboard',
        merchant_id: current_merchant&.id,
        question: msg,
        selected_agent: out.agent_key,
        selected_retriever: selected_retriever,
        graph_enabled: ENV['AI_CONTEXT_GRAPH_ENABLED'].to_s.strip.downcase.in?(%w[true 1]),
        vector_enabled: ENV['AI_VECTOR_RAG_ENABLED'].to_s.strip.downcase.in?(%w[true 1]),
        memory_used: memory_result&.dig(:memory_used),
        summary_used: memory_result&.dig(:summary_used),
        recent_messages_count: recent_count,
        retrieved_sections_count: out.citations.size,
        citations_count: out.citations.size,
        fallback_used: out.fallback_used,
        citation_reask_used: out.metadata[:guardrail_reask],
        model_used: out.model_used,
        latency_ms: latency_ms,
        success: true
      )
    end

    def log_ai_request_error(e, msg, agent_key, retriever_result, selected_retriever, latency_ms)
      ::Ai::Observability::EventLogger.log_ai_request(
        request_id: request.request_id,
        endpoint: 'dashboard',
        merchant_id: current_merchant&.id,
        question: msg,
        selected_agent: agent_key&.to_s,
        selected_retriever: selected_retriever,
        graph_enabled: ENV['AI_CONTEXT_GRAPH_ENABLED'].to_s.strip.downcase.in?(%w[true 1]),
        vector_enabled: ENV['AI_VECTOR_RAG_ENABLED'].to_s.strip.downcase.in?(%w[true 1]),
        memory_used: nil,
        summary_used: nil,
        recent_messages_count: nil,
        retrieved_sections_count: retriever_result&.dig(:citations)&.size,
        citations_count: retriever_result&.dig(:citations)&.size,
        fallback_used: nil,
        citation_reask_used: nil,
        model_used: nil,
        latency_ms: latency_ms,
        success: false,
        error_class: e.class.name,
        error_message: e.message
      )
    end

    def build_debug_payload(out, agent_key, selected_retriever, retriever_result, latency_ms, memory_result)
      debug = ::Ai::Observability::EventLogger.build_debug_payload(
        selected_agent: out.agent_key,
        selected_retriever: selected_retriever,
        graph_enabled: ENV['AI_CONTEXT_GRAPH_ENABLED'].to_s.strip.downcase.in?(%w[true 1]),
        vector_enabled: ENV['AI_VECTOR_RAG_ENABLED'].to_s.strip.downcase.in?(%w[true 1]),
        retrieved_sections_count: retriever_result&.dig(:final_sections_count) || retriever_result&.dig(:citations)&.size,
        citations_count: out.citations.size,
        fallback_used: out.fallback_used,
        citation_reask_used: out.metadata[:guardrail_reask],
        model_used: out.model_used,
        memory_used: memory_result&.dig(:memory_used),
        summary_used: memory_result&.dig(:summary_used),
        latency_ms: latency_ms,
        retriever_debug: retriever_result&.dig(:debug)
      )
      retriever_debug = retriever_result&.dig(:debug)
      debug.merge!(retriever_debug.symbolize_keys) if retriever_debug.is_a?(Hash) && retriever_debug.present?
      debug[:context_truncated] = retriever_result[:context_truncated] if retriever_result
      debug[:final_context_chars] = retriever_result[:final_context_chars] if retriever_result
      debug[:final_sections_count] = retriever_result[:final_sections_count] if retriever_result
      debug[:memory_truncated] = memory_result[:memory_truncated] if memory_result
      debug[:final_memory_chars] = memory_result[:final_memory_chars] if memory_result
      debug[:recent_messages_count] = memory_result[:recent_messages_count] if memory_result
      debug[:summary_updated] = memory_result[:summary_updated] if memory_result
      debug[:summary_chars] = memory_result[:summary_chars] if memory_result
      debug[:current_topic] = memory_result[:current_topic] if memory_result
      debug[:sanitization_applied] = memory_result[:sanitization_applied] if memory_result
      debug
    end
  end
end
