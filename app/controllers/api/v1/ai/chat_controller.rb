# frozen_string_literal: true

module Api
  module V1
    module Ai
      class ChatController < Api::V1::BaseController
        AI_RATE_LIMIT = 20
        AI_RATE_WINDOW = 60

        def create
          if ai_rate_limited?
            return render_error(
              code: 'rate_limited',
              message: "AI chat limit: #{AI_RATE_LIMIT} requests per #{AI_RATE_WINDOW} seconds.",
              status: :too_many_requests
            )
          end

          message = chat_params[:message].to_s.strip
          if message.blank?
            return render_error(
              code: 'validation_error',
              message: 'message is required',
              status: :bad_request
            )
          end

          Thread.current[:ai_request_id] = request.request_id
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          retriever_result = nil
          out = nil
          agent_key = nil
          selected_retriever = nil

          agent_key = ::Ai::Router.new(message).call
          retriever_result = ::Ai::Rag::RetrievalService.call(message, agent_key: agent_key)
          selected_retriever = retriever_result.dig(:debug, :retriever).presence || resolve_retriever_name
          context_text = retriever_result[:context_text]
          citations = retriever_result[:citations]

          agent_class = ::Ai::AgentRegistry.fetch(agent_key)
          agent = build_agent(agent_class, agent_key, message, context_text, citations)
          out = agent.call

          latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
          increment_ai_chat_count

          log_ai_request_success(out, message, agent_key, retriever_result, selected_retriever, latency_ms)

          payload = build_chat_payload(out)
          payload[:debug] = build_debug_payload(out, agent_key, selected_retriever, retriever_result, latency_ms) if ai_debug?
          render json: payload
        rescue StandardError => e
          latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
          log_ai_request_error(e, message, agent_key, retriever_result, selected_retriever, latency_ms)
          raise
        end

        private

        def resolve_retriever_name
          graph = ENV['AI_CONTEXT_GRAPH_ENABLED'].to_s.strip.downcase.in?(%w[true 1])
          vector = ENV['AI_VECTOR_RAG_ENABLED'].to_s.strip.downcase.in?(%w[true 1])
          graph ? 'GraphExpandedRetriever' : (vector ? 'HybridRetriever' : 'DocsRetriever')
        end

        def log_ai_request_success(out, message, agent_key, retriever_result, selected_retriever, latency_ms)
          ::Ai::Observability::EventLogger.log_ai_request(
            request_id: request.request_id,
            endpoint: 'api',
            merchant_id: current_merchant&.id,
            question: message,
            selected_agent: out.agent_key,
            selected_retriever: selected_retriever,
            graph_enabled: ENV['AI_CONTEXT_GRAPH_ENABLED'].to_s.strip.downcase.in?(%w[true 1]),
            vector_enabled: ENV['AI_VECTOR_RAG_ENABLED'].to_s.strip.downcase.in?(%w[true 1]),
            memory_used: false,
            summary_used: out.metadata[:summary_used],
            recent_messages_count: 0,
            retrieved_sections_count: out.citations.size,
            citations_count: out.citations.size,
            fallback_used: out.fallback_used,
            citation_reask_used: out.metadata[:guardrail_reask],
            model_used: out.model_used,
            latency_ms: latency_ms,
            success: true
          )
        end

        def log_ai_request_error(e, message, agent_key, retriever_result, selected_retriever, latency_ms)
          ::Ai::Observability::EventLogger.log_ai_request(
            request_id: request.request_id,
            endpoint: 'api',
            merchant_id: current_merchant&.id,
            question: message,
            selected_agent: agent_key&.to_s,
            selected_retriever: selected_retriever,
            graph_enabled: ENV['AI_CONTEXT_GRAPH_ENABLED'].to_s.strip.downcase.in?(%w[true 1]),
            vector_enabled: ENV['AI_VECTOR_RAG_ENABLED'].to_s.strip.downcase.in?(%w[true 1]),
            memory_used: false,
            summary_used: nil,
            recent_messages_count: 0,
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

        def build_chat_payload(out)
          payload = { reply: out.reply_text, agent: out.agent_key, citations: out.citations }
          payload[:data] = out.data if out.data.present?
          payload
        end

        def build_debug_payload(out, agent_key, selected_retriever, retriever_result, latency_ms)
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
            memory_used: false,
            summary_used: out.metadata[:summary_used],
            latency_ms: latency_ms,
            retriever_debug: retriever_result&.dig(:debug)
          )
          debug[:context_truncated] = retriever_result[:context_truncated] if retriever_result
          debug[:final_context_chars] = retriever_result[:final_context_chars] if retriever_result
          debug[:final_sections_count] = retriever_result[:final_sections_count] if retriever_result
          debug
        end

        def ai_debug?
          ::Ai::Observability::EventLogger.ai_debug_enabled?
        end

        def build_agent(agent_class, agent_key, message, context_text, citations)
          if agent_key == :reporting_calculation
            agent_class.new(merchant_id: current_merchant.id, message: message, context_text: context_text, citations: citations)
          else
            agent_class.new(message: message, context_text: context_text, citations: citations)
          end
        end

        def chat_params
          params.permit(:message)
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
      end
    end
  end
end
