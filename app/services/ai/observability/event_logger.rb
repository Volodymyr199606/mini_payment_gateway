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

        # Log deterministic tool calls. Safe args only (no secrets).
        def log_tool_call(
          request_id: nil,
          merchant_id: nil,
          tool_name: nil,
          args: nil,
          success: nil,
          latency_ms: nil,
          authorization_denied: nil,
          tool_blocked_by_policy: nil
        )
          payload = build_base_payload.merge(
            event: 'ai_tool_call',
            request_id: request_id,
            merchant_id: merchant_id,
            tool_name: tool_name,
            args: args,
            success: success,
            latency_ms: latency_ms
          )
          payload[:authorization_denied] = authorization_denied if authorization_denied.present?
          payload[:tool_blocked_by_policy] = tool_blocked_by_policy if tool_blocked_by_policy.present?
          log_info(payload)
        end

        # Log constrained orchestration run (step count, tool names, success, halted_reason).
        def log_orchestration_run(
          request_id: nil,
          merchant_id: nil,
          step_count: nil,
          tool_names: nil,
          success: nil,
          halted_reason: nil,
          latency_ms: nil
        )
          payload = build_base_payload.merge(
            event: 'ai_orchestration_run',
            request_id: request_id,
            merchant_id: merchant_id,
            step_count: step_count,
            tool_names: tool_names,
            success: success,
            halted_reason: halted_reason,
            latency_ms: latency_ms
          )
          log_info(payload)
        end

        # Log resilience/fallback events.
        def log_resilience(
          degraded: nil,
          failure_stage: nil,
          fallback_mode: nil,
          original_path: nil,
          final_path_used: nil,
          retry_attempted: nil,
          success_after_fallback: nil,
          request_id: nil
        )
          payload = build_base_payload.merge(
            event: 'ai_resilience',
            degraded: degraded,
            failure_stage: failure_stage,
            fallback_mode: fallback_mode,
            original_path: original_path,
            final_path_used: final_path_used,
            retry_attempted: retry_attempted,
            success_after_fallback: success_after_fallback,
            request_id: request_id
          )
          log_info(payload)
        end

        # Log execution planning (cost/latency control).
        def log_execution_plan(
          execution_mode: nil,
          retrieval_skipped: nil,
          memory_skipped: nil,
          orchestration_skipped: nil,
          retrieval_budget_reduced: nil,
          reason_codes: nil,
          request_id: nil
        )
          payload = build_base_payload.merge(
            event: 'ai_execution_plan',
            execution_mode: execution_mode,
            retrieval_skipped: retrieval_skipped,
            memory_skipped: memory_skipped,
            orchestration_skipped: orchestration_skipped,
            retrieval_budget_reduced: retrieval_budget_reduced,
            reason_codes: reason_codes,
            request_id: request_id
          )
          log_info(payload)
        end

        # Log cache events: hit, miss, bypassed.
        def log_cache(
          cache_category: nil,
          cache_key_fingerprint: nil,
          cache_outcome: nil,
          cache_ttl: nil,
          cache_bypass_reason: nil,
          cache_result_keys: nil
        )
          payload = build_base_payload.merge(
            event: 'ai_cache',
            cache_category: cache_category,
            cache_key_fingerprint: cache_key_fingerprint,
            cache_outcome: cache_outcome,
            cache_ttl: cache_ttl
          )
          payload[:cache_bypass_reason] = cache_bypass_reason if cache_bypass_reason.present?
          payload[:cache_result_keys] = cache_result_keys if cache_result_keys.is_a?(Array)
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
          retriever_debug: nil,
          authorization_denied: nil,
          tool_blocked_by_policy: nil,
          followup_inheritance_blocked: nil,
          policy_reason_code: nil,
          policy_decision_types: nil,
          cache_metadata: nil,
          resilience_metadata: nil,
          execution_plan: nil
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
          debug[:authorization_checked] = true
          debug[:authorization_denied] = authorization_denied if authorization_denied.present?
          debug[:tool_blocked_by_policy] = tool_blocked_by_policy if tool_blocked_by_policy.present?
          debug[:followup_inheritance_blocked] = followup_inheritance_blocked if followup_inheritance_blocked.present?
          debug[:policy_reason_code] = policy_reason_code if policy_reason_code.present?
          debug[:policy_decision_types] = policy_decision_types if policy_decision_types.is_a?(Array) && policy_decision_types.any?
          if cache_metadata.is_a?(Hash) && cache_metadata.present?
            debug[:cache] = cache_metadata.slice(:retrieval_outcome, :memory_outcome, :cache_bypassed)
          end
          if resilience_metadata.is_a?(Hash) && resilience_metadata.present?
            debug[:resilience] = resilience_metadata.slice(:degraded, :failure_stage, :fallback_mode)
          end
          if execution_plan.respond_to?(:execution_mode)
            debug[:execution_plan] = {
              execution_mode: execution_plan.execution_mode,
              retrieval_skipped: !!execution_plan.skip_retrieval,
              memory_skipped: !!execution_plan.skip_memory,
              orchestration_skipped: !!execution_plan.skip_orchestration,
              retrieval_budget_reduced: !!execution_plan.retrieval_budget_reduced,
              reason_codes: Array(execution_plan.reason_codes)
            }.compact
          end
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
