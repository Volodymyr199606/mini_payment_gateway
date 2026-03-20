# frozen_string_literal: true

module Api
  module V1
    module Ai
      class ChatController < Api::V1::BaseController
        def create
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
          retriever_result = ::Ai::Performance::CachedRetrievalService.call(message, agent_key: agent_key)
          selected_retriever = retriever_result.dig(:debug, :retriever).presence || resolve_retriever_name
          context_text = retriever_result[:context_text]
          citations = retriever_result[:citations]

          agent_class = ::Ai::AgentRegistry.fetch(agent_key)
          agent = build_agent(agent_class, agent_key, message, context_text, citations)
          out = agent.call

          latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round

          log_ai_request_success(out, message, agent_key, retriever_result, selected_retriever, latency_ms)

          write_ai_audit(
            request_id: request.request_id,
            endpoint: 'api',
            merchant_id: current_merchant&.id,
            agent_key: out.agent_key,
            retriever_key: selected_retriever,
            tool_used: false,
            fallback_used: out.fallback_used,
            citation_reask_used: out.metadata[:guardrail_reask],
            memory_used: false,
            summary_used: out.metadata[:summary_used],
            citations_count: out.citations.size,
            retrieved_sections_count: retriever_result&.dig(:final_sections_count) || retriever_result&.dig(:citations)&.size,
            latency_ms: latency_ms,
            model_used: out.model_used,
            success: true
          )

          payload = build_chat_payload(out)
          payload[:debug] = build_debug_payload(out, agent_key, selected_retriever, retriever_result, latency_ms) if ai_debug?
          render json: payload
        rescue StandardError => e
          latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
          payload = apply_resilience_fallback(e, message, agent_key, retriever_result, selected_retriever, latency_ms)
          render json: payload
        end

        private

        def resolve_retriever_name
          graph = ::Ai::Config::FeatureFlags.ai_graph_retrieval_enabled?
          vector = ::Ai::Config::FeatureFlags.ai_vector_retrieval_enabled?
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
            graph_enabled: ::Ai::Config::FeatureFlags.ai_graph_retrieval_enabled?,
            vector_enabled: ::Ai::Config::FeatureFlags.ai_vector_retrieval_enabled?,
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
            graph_enabled: ::Ai::Config::FeatureFlags.ai_graph_retrieval_enabled?,
            vector_enabled: ::Ai::Config::FeatureFlags.ai_vector_retrieval_enabled?,
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
            graph_enabled: ::Ai::Config::FeatureFlags.ai_graph_retrieval_enabled?,
            vector_enabled: ::Ai::Config::FeatureFlags.ai_vector_retrieval_enabled?,
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

        def write_ai_audit(**attrs)
          attrs[:corpus_version] ||= current_corpus_version if audit_has_corpus_version?
          record = ::Ai::AuditTrail::RecordBuilder.call(**attrs)
          ::Ai::AuditTrail::Writer.write(record)
        end

        def current_corpus_version
          @current_corpus_version ||= ::Ai::Rag::Corpus::StateService.call.corpus_version
        end

        def audit_has_corpus_version?
          AiRequestAudit.column_names.include?('corpus_version')
        end

        def apply_resilience_fallback(e, message, agent_key, retriever_result, selected_retriever, latency_ms)
          stage = ::Ai::Resilience::Coordinator.infer_stage(e)
          context = { context_text: retriever_result&.dig(:context_text), tool_data: nil, original_path: 'api' }
          decision = ::Ai::Resilience::Coordinator.plan_fallback(failure_stage: stage, context: context, exception: e)
          safe = ::Ai::Resilience::Coordinator.build_safe_response(decision: decision, context: context)

          safe_audit { log_ai_request_error(e, message, agent_key, retriever_result, selected_retriever, latency_ms) }
          ::Ai::Observability::EventLogger.log_resilience(
            degraded: true, failure_stage: stage, fallback_mode: decision.fallback_mode,
            original_path: 'api', final_path_used: decision.fallback_mode, success_after_fallback: true, request_id: request.request_id
          )
          resilience_meta = { degraded: true, failure_stage: stage, fallback_mode: decision.fallback_mode, success_after_fallback: true }
          safe_audit do
            write_ai_audit(
              request_id: request.request_id, endpoint: 'api', merchant_id: current_merchant&.id,
              agent_key: 'resilience_fallback', retriever_key: selected_retriever,
              citations_count: retriever_result&.dig(:citations)&.size,
              retrieved_sections_count: retriever_result&.dig(:final_sections_count) || retriever_result&.dig(:citations)&.size,
              latency_ms: latency_ms, success: false, error_class: e.class.name, error_message: e.message.to_s[0, 500],
              resilience_metadata: resilience_meta
            )
          end

          payload = build_resilience_payload(safe)
          payload[:debug] = build_debug_payload_for_resilience(safe, selected_retriever, retriever_result, latency_ms, resilience_meta) if ai_debug?
          payload
        end

        def safe_audit
          yield
        rescue StandardError => err
          Rails.logger.warn("[AI] Audit failed (non-blocking): #{err.class} #{err.message}")
        end

        def build_resilience_payload(safe)
          { reply: safe[:reply], agent: safe[:agent_key], citations: safe[:citations], fallback_used: true }.tap do |p|
            p[:data] = safe[:data] if safe[:data].present?
          end
        end

        def build_debug_payload_for_resilience(safe, selected_retriever, retriever_result, latency_ms, resilience_meta)
          ::Ai::Observability::EventLogger.build_debug_payload(
            selected_agent: 'resilience_fallback',
            selected_retriever: selected_retriever,
            fallback_used: true,
            latency_ms: latency_ms,
            resilience_metadata: resilience_meta
          )
        end

        def chat_params
          params.permit(:message)
        end

      end
    end
  end
end
