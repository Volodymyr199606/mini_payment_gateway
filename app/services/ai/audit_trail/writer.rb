# frozen_string_literal: true

module Ai
  module AuditTrail
    # Persists one AI request audit record. Sanitizes values and never raises into the request flow.
    class Writer
      ERROR_MESSAGE_MAX_LEN = 500
      REQUEST_ID_MAX_LEN = 128
      ENDPOINT_MAX_LEN = 64
      AGENT_KEY_MAX_LEN = 128
      RETRIEVER_KEY_MAX_LEN = 64
      COMPOSITION_MODE_MAX_LEN = 32
      MODEL_USED_MAX_LEN = 64
      ERROR_CLASS_MAX_LEN = 256
      TOOL_NAMES_MAX = 20

      # Secrets / tokens we redact from error_message if present
      REDACT_PATTERNS = [
        /\b(?:sk|pk)_[a-zA-Z0-9_]+\b/i,
        /\b(?:api[_\s]?key|apikey)\s*[:=]\s*['"]?[^\s'"]+['"]?/i,
        /\b(?:bearer|token)\s+[a-zA-Z0-9_.-]+/i
      ].freeze

      class << self
        # @param record [Hash] output from RecordBuilder or equivalent
        # @return [AiRequestAudit, nil] created record or nil on failure (never raises)
        def write(record)
          return nil unless record.is_a?(Hash)

          attrs = sanitize(record)
          valid_attrs = attrs.slice(*AiRequestAudit.column_names.map(&:to_sym))
          AiRequestAudit.create!(valid_attrs)
        rescue StandardError => e
          Rails.logger.warn("[Ai::AuditTrail::Writer] Failed to persist audit: #{e.class} #{e.message}")
          nil
        end

        private

        def sanitize(record)
          err_msg = record[:error_message].to_s
          REDACT_PATTERNS.each { |re| err_msg = err_msg.gsub(re, '[REDACTED]') }
          err_msg = err_msg.truncate(ERROR_MESSAGE_MAX_LEN) if err_msg.length > ERROR_MESSAGE_MAX_LEN

          tool_names = Array(record[:tool_names]).first(TOOL_NAMES_MAX).map(&:to_s).reject(&:blank?)

          {
            request_id: record[:request_id].to_s.truncate(REQUEST_ID_MAX_LEN),
            endpoint: record[:endpoint].to_s.truncate(ENDPOINT_MAX_LEN),
            merchant_id: record[:merchant_id],
            agent_key: record[:agent_key].to_s.truncate(AGENT_KEY_MAX_LEN),
            retriever_key: record[:retriever_key].to_s.truncate(RETRIEVER_KEY_MAX_LEN).presence,
            composition_mode: record[:composition_mode].to_s.truncate(COMPOSITION_MODE_MAX_LEN).presence,
            tool_used: !!record[:tool_used],
            tool_names: tool_names,
            fallback_used: !!record[:fallback_used],
            citation_reask_used: !!record[:citation_reask_used],
            memory_used: !!record[:memory_used],
            summary_used: !!record[:summary_used],
            parsed_entities: record[:parsed_entities].is_a?(Hash) ? record[:parsed_entities] : {},
            parsed_intent_hints: record[:parsed_intent_hints].is_a?(Hash) ? record[:parsed_intent_hints] : {},
            citations_count: record[:citations_count].to_i,
            retrieved_sections_count: record[:retrieved_sections_count],
            latency_ms: record[:latency_ms],
            model_used: record[:model_used].to_s.truncate(MODEL_USED_MAX_LEN).presence,
            success: !!record[:success],
            error_class: record[:error_class].to_s.truncate(ERROR_CLASS_MAX_LEN).presence,
            error_message: err_msg.presence,
            followup_detected: !!record[:followup_detected],
            followup_type: record[:followup_type].to_s.strip.truncate(64).presence,
            authorization_denied: !!record[:authorization_denied],
            policy_reason_code: record[:policy_reason_code].to_s.strip.truncate(64).presence,
            tool_blocked_by_policy: !!record[:tool_blocked_by_policy],
            followup_inheritance_blocked: !!record[:followup_inheritance_blocked],
            created_at: Time.current
          }.tap do |h|
            h[:corpus_version] = record[:corpus_version].to_s.strip.truncate(64).presence if record.key?(:corpus_version)
          end
        end
      end
    end
  end
end
