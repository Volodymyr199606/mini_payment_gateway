# frozen_string_literal: true

module Ai
  module Observability
    # Structured logging for AI requests, retrieval, and guardrails.
    # Uses Rails.logger with JSON payload for production-like observability.
    class EventLogger
      QUESTION_TRUNCATE = 200

      class << self
        # Log full AI chat request. Call from controllers after agent.call.
        def log_ai_request(
          request_id: nil,
          endpoint: nil,
          merchant_id: nil,
          question: nil,
          selected_agent: nil,
          selected_retriever: nil,
          graph_enabled: nil,
          vector_enabled: nil,
          memory_used: nil,
          summary_used: nil,
          recent_messages_count: nil,
          retrieved_sections_count: nil,
          citations_count: nil,
          fallback_used: nil,
          citation_reask_used: nil,
          model_used: nil,
          fallback_model_used: nil,
          latency_ms: nil,
          success: true,
          error_class: nil,
          error_message: nil
        )
          payload = build_base_payload.merge(
            event: 'ai_request',
            request_id: request_id,
            endpoint: endpoint,
            merchant_id: merchant_id,
            question: truncate_safe(question, QUESTION_TRUNCATE),
            selected_agent: selected_agent,
            selected_retriever: selected_retriever,
            graph_enabled: graph_enabled,
            vector_enabled: vector_enabled,
            memory_used: memory_used,
            summary_used: summary_used,
            recent_messages_count: recent_messages_count,
            retrieved_sections_count: retrieved_sections_count,
            citations_count: citations_count,
            fallback_used: fallback_used,
            citation_reask_used: citation_reask_used,
            model_used: model_used,
            fallback_model_used: fallback_model_used,
            latency_ms: latency_ms,
            success: success
          )
          payload[:error_class] = error_class if error_class.present?
          payload[:error_message] = truncate_safe(error_message, 500) if error_message.present?
          log_info(payload)
        end

        # Log retrieval stage. Called from RetrievalService.
        def log_retrieval(
          retriever: nil,
          query: nil,
          agent_key: nil,
          seed_sections_count: nil,
          expanded_sections_count: nil,
          vector_hits_count: nil,
          final_sections_count: nil,
          context_text_length: nil,
          context_truncated: nil,
          citations_count: nil,
          request_id: nil
        )
          payload = build_base_payload.merge(
            event: 'ai_retrieval',
            retriever: retriever,
            query: truncate_safe(query, QUESTION_TRUNCATE),
            agent_key: agent_key,
            seed_sections_count: seed_sections_count,
            expanded_sections_count: expanded_sections_count,
            vector_hits_count: vector_hits_count,
            final_sections_count: final_sections_count,
            context_text_length: context_text_length,
            context_truncated: context_truncated,
            citations_count: citations_count,
            request_id: request_id
          )
          log_info(payload)
        end

        # Log guardrail events: empty_retrieval_fallback, citation_reask, secret_redaction, safe_fallback.
        def log_guardrail(
          event: nil,
          request_id: nil,
          agent_key: nil,
          citations_count: nil,
          context_length: nil,
          **extra
        )
          payload = build_base_payload.merge(
            event: "ai_guardrail_#{event}".to_sym,
            request_id: request_id,
            agent_key: agent_key,
            citations_count: citations_count,
            context_length: context_length,
            **extra
          )
          log_info(payload)
        end

        # Build debug payload for AI_DEBUG responses. Non-sensitive only.
        def build_debug_payload(
          selected_agent: nil,
          selected_retriever: nil,
          graph_enabled: nil,
          vector_enabled: nil,
          retrieved_sections_count: nil,
          citations_count: nil,
          fallback_used: nil,
          citation_reask_used: nil,
          model_used: nil,
          memory_used: nil,
          summary_used: nil,
          latency_ms: nil,
          retriever_debug: nil
        )
          debug = {
            selected_agent: selected_agent,
            selected_retriever: selected_retriever,
            graph_enabled: graph_enabled,
            vector_enabled: vector_enabled,
            retrieved_sections_count: retrieved_sections_count,
            citations_count: citations_count,
            fallback_used: fallback_used,
            citation_reask_used: citation_reask_used,
            model_used: model_used,
            memory_used: memory_used,
            summary_used: summary_used,
            latency_ms: latency_ms
          }
          debug[:retriever] = retriever_debug if retriever_debug.is_a?(Hash) && retriever_debug.present?
          debug
        end

        def ai_debug_enabled?
          v = ENV['AI_DEBUG'].to_s.strip.downcase
          v == 'true' || v == '1'
        end

        private

        def build_base_payload
          {
            timestamp: Time.current.iso8601,
            service: 'mini_payment_gateway'
          }
        end

        def log_info(payload)
          Rails.logger.info(payload.compact.to_json)
        end

        def truncate_safe(str, max_len)
          return nil if str.blank?
          s = str.to_s
          s.length <= max_len ? s : "#{s[0, max_len]}..."
        end
      end
    end
  end
end
