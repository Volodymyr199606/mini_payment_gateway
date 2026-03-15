# frozen_string_literal: true

module Ai
  module AuditTrail
    # Builds a normalized metadata hash for one AI request from pipeline/observability data.
    # Reuses the same inputs as EventLogger where possible. No prompts or secrets.
    class RecordBuilder
      def self.call(**inputs)
        new(**inputs).call
      end

      def initialize(
        request_id: nil,
        endpoint: nil,
        merchant_id: nil,
        agent_key: nil,
        retriever_key: nil,
        composition: nil,
        tool_used: false,
        tool_names: nil,
        fallback_used: false,
        citation_reask_used: false,
        memory_used: false,
        summary_used: false,
        parsed_entities: nil,
        parsed_intent_hints: nil,
        citations_count: 0,
        retrieved_sections_count: nil,
        latency_ms: nil,
        model_used: nil,
        success: true,
        error_class: nil,
        error_message: nil,
        orchestration_used: false,
        orchestration_step_count: nil,
        orchestration_halted_reason: nil,
        followup_metadata: nil,
        policy_metadata: nil,
        resilience_metadata: nil,
        execution_plan_metadata: nil,
        corpus_version: nil
      )
        @request_id = request_id.to_s.strip.presence
        @endpoint = endpoint.to_s.strip.presence
        @merchant_id = merchant_id
        @agent_key = agent_key.to_s.strip.presence
        @retriever_key = retriever_key.to_s.strip.presence
        @composition = composition.is_a?(Hash) ? composition : {}
        @tool_used = !!tool_used
        @tool_names = Array(tool_names).map(&:to_s).reject(&:blank?)
        @fallback_used = !!fallback_used
        @citation_reask_used = !!citation_reask_used
        @memory_used = !!memory_used
        @summary_used = !!summary_used
        @parsed_entities = normalize_json_input(parsed_entities)
        @parsed_intent_hints = normalize_json_input(parsed_intent_hints)
        @citations_count = citations_count.to_i
        @retrieved_sections_count = retrieved_sections_count
        @latency_ms = latency_ms
        @model_used = model_used.to_s.strip.presence
        @success = !!success
        @error_class = error_class.to_s.strip.presence
        @error_message = error_message
        @orchestration_used = !!orchestration_used
        @orchestration_step_count = orchestration_step_count.to_i if orchestration_step_count.present?
        @orchestration_halted_reason = orchestration_halted_reason.to_s.strip.presence
        @followup_metadata = followup_metadata
        @policy_metadata = policy_metadata
        @resilience_metadata = resilience_metadata
        @execution_plan_metadata = execution_plan_metadata
        @corpus_version = corpus_version.to_s.strip.presence
      end

      def call
        out = {
          request_id: @request_id,
          endpoint: @endpoint,
          merchant_id: @merchant_id,
          agent_key: @agent_key || 'unknown',
          retriever_key: @retriever_key,
          composition_mode: @composition[:composition_mode].to_s.strip.presence,
          tool_used: @tool_used,
          tool_names: @tool_names,
          fallback_used: @fallback_used,
          citation_reask_used: @citation_reask_used,
          memory_used: @memory_used,
          summary_used: @summary_used,
          parsed_entities: @parsed_entities,
          parsed_intent_hints: @parsed_intent_hints,
          citations_count: @citations_count,
          retrieved_sections_count: @retrieved_sections_count,
          latency_ms: @latency_ms,
          model_used: @model_used,
          success: @success,
          error_class: @error_class,
          error_message: @error_message
        }
        out[:orchestration_used] = @orchestration_used if @orchestration_used
        out[:orchestration_step_count] = @orchestration_step_count if @orchestration_step_count.to_i.positive?
        out[:orchestration_halted_reason] = @orchestration_halted_reason if @orchestration_halted_reason.present?
        if @followup_metadata.is_a?(Hash) && @followup_metadata[:followup_detected]
          out[:followup_detected] = true
          out[:followup_type] = @followup_metadata[:followup_type].to_s.strip.presence
        end
        if @policy_metadata.is_a?(Hash)
          out[:authorization_denied] = !!@policy_metadata[:authorization_denied]
          out[:tool_blocked_by_policy] = !!@policy_metadata[:tool_blocked_by_policy]
          out[:followup_inheritance_blocked] = !!@policy_metadata[:followup_inheritance_blocked]
          out[:policy_reason_code] = @policy_metadata[:policy_reason_code].to_s.strip.presence
        end
        if @resilience_metadata.is_a?(Hash)
          out[:degraded] = !!@resilience_metadata[:degraded]
          out[:failure_stage] = @resilience_metadata[:failure_stage].to_s.strip.presence
          out[:fallback_mode] = @resilience_metadata[:fallback_mode].to_s.strip.presence
          out[:success_after_fallback] = !!@resilience_metadata[:success_after_fallback] if @resilience_metadata.key?(:success_after_fallback)
        end
        if @execution_plan_metadata.is_a?(Hash)
          out[:execution_mode] = @execution_plan_metadata[:execution_mode].to_s.strip.presence
          out[:retrieval_skipped] = !!@execution_plan_metadata[:retrieval_skipped]
          out[:memory_skipped] = !!@execution_plan_metadata[:memory_skipped]
          out[:retrieval_budget_reduced] = !!@execution_plan_metadata[:retrieval_budget_reduced]
        end
        out[:corpus_version] = @corpus_version if @corpus_version.present?
        if @composition.is_a?(Hash)
          out[:deterministic_explanation_used] = true if @composition[:deterministic_explanation_used]
          out[:explanation_type] = @composition[:explanation_type].to_s.strip.presence if @composition[:explanation_type].present?
          out[:explanation_key] = @composition[:explanation_key].to_s.strip.truncate(64).presence if @composition[:explanation_key].present?
        end
        out[:schema_version] = (defined?(Ai::Contracts) && Ai::Contracts::AUDIT_PAYLOAD_VERSION) || '1'
        out
      end

      private

      def normalize_json_input(val)
        return {} if val.nil?
        return val if val.is_a?(Hash) && val.keys.all? { |k| k.is_a?(String) || k.is_a?(Symbol) }
        return {} unless val.respond_to?(:to_h)

        val.to_h.slice(*%w[type ids hints]).transform_keys(&:to_s)
      rescue StandardError
        {}
      end
    end
  end
end
