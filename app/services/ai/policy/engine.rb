# frozen_string_literal: true

module Ai
  module Policy
    # Unified AI policy engine. Single governance layer for AI behavior and allowed actions.
    # Coordinates: authorization, memory boundaries, tool permissions, orchestration,
    # source composition, and debug exposure. Delegates to Authorization for record/entity checks.
    class Engine
      DECISION_TYPES = %i[
        tool orchestration memory_reuse followup_inheritance
        source_composition debug_exposure deterministic_data docs_fallback
      ].freeze

      REASON_MERCHANT_REQUIRED = 'merchant_required'
      REASON_ORCHESTRATION_BLOCKED = 'orchestration_blocked'
      REASON_DEBUG_RESTRICTED = 'debug_restricted'
      REASON_SOURCE_COMPOSITION_BLOCKED = 'source_composition_blocked'

      def self.call(context:, parsed_request: nil)
        new(context: context, parsed_request: parsed_request)
      end

      def initialize(context:, parsed_request: nil)
        @context = context.to_h.stringify_keys
        @parsed_request = parsed_request || {}
        @merchant_id = @context['merchant_id']&.to_i
        @auth = Authorization.call(context: @context)
      end

      # Whether a tool may run for the current context and parsed request.
      def allow_tool?(tool_name:, context: nil, parsed_request: nil)
        ctx = context || @context
        pr = parsed_request || @parsed_request
        d = @auth.allow_tool?(tool_name: tool_name, args: pr[:args].to_h)
        wrap_decision(d, :tool)
      end

      # Whether orchestration is allowed (intent clear, merchant present, no policy block).
      def allow_orchestration?(context: nil, parsed_request: nil)
        ctx = context || @context
        pr = parsed_request || @parsed_request
        return Decision.deny(reason_code: REASON_MERCHANT_REQUIRED, decision_type: :orchestration) unless @merchant_id.present?
        return Decision.deny(reason_code: REASON_ORCHESTRATION_BLOCKED, decision_type: :orchestration, metadata: { reason: 'no_intent' }) if pr[:intent].blank? && pr[:resolved_intent].blank?

        Decision.allow(decision_type: :orchestration, metadata: {})
      end

      # Whether prior memory may be reused (merchant/session boundary).
      def allow_memory_reuse?(context: nil, memory_candidate:, parsed_request: nil)
        ctx = context || @context
        return Decision.deny(reason_code: REASON_MERCHANT_REQUIRED, decision_type: :memory_reuse) unless @merchant_id.present?

        # Memory is merchant-scoped by construction; no cross-tenant reuse.
        Decision.allow(decision_type: :memory_reuse, metadata: {})
      end

      # Whether inherited entity/time/topic from follow-up may be reused.
      def allow_followup_inheritance?(context: nil, inherited_item:, parsed_request: nil)
        ctx = context || @context
        entity_type = inherited_item[:entity_type] || inherited_item['entity_type']
        entity_id = inherited_item[:entity_id] || inherited_item['entity_id']
        return Decision.deny(reason_code: 'entity_invalid', decision_type: :followup_inheritance) if entity_type.blank? || entity_id.blank?

        d = @auth.allow_followup_inheritance?(entity_type: entity_type, entity_id: entity_id)
        wrap_decision(d, :followup_inheritance)
      end

      # Whether response composition may combine the given source types (tool, docs, memory).
      def allow_source_composition?(source_types:, context: nil, parsed_request: nil)
        ctx = context || @context
        return Decision.deny(reason_code: REASON_MERCHANT_REQUIRED, decision_type: :source_composition) unless @merchant_id.present?

        types = Array(source_types).map(&:to_s)
        # Allow tool_only, docs_only, hybrid_tool_docs, memory_docs, memory_tool_docs.
        return Decision.deny(reason_code: REASON_SOURCE_COMPOSITION_BLOCKED, decision_type: :source_composition, metadata: { source_types: types }) if types.any? { |t| t == 'raw_payload' || t == 'internal' }

        Decision.allow(decision_type: :source_composition, metadata: { source_types: types })
      end

      # Whether debug payload may be exposed (AI_DEBUG and no secrets).
      def allow_debug_exposure?(context: nil, debug_payload: nil)
        ctx = context || @context
        return Decision.deny(reason_code: REASON_DEBUG_RESTRICTED, decision_type: :debug_exposure) unless ai_debug_enabled?

        payload = debug_payload.to_h
        return Decision.deny(reason_code: REASON_DEBUG_RESTRICTED, decision_type: :debug_exposure, metadata: { reason: 'unsafe_content' }) if payload.key?(:prompt) || payload.key?('prompt') || payload.key?(:api_key) || payload.key?('api_key')

        Decision.allow(decision_type: :debug_exposure, metadata: {})
      end

      # Whether deterministic data for the resource type may be exposed to the caller.
      def allow_deterministic_data_exposure?(resource_type:, context: nil, parsed_request: nil, data: nil)
        ctx = context || @context
        return Decision.deny(reason_code: REASON_MERCHANT_REQUIRED, decision_type: :deterministic_data) unless @merchant_id.present?

        return Decision.allow(decision_type: :deterministic_data) if data.blank?

        d = @auth.allow_composed_data?(source_type: resource_type, data: data)
        wrap_decision(d, :deterministic_data)
      end

      # Whether docs-only fallback is allowed when deterministic path is blocked.
      def allow_docs_only_fallback?(context: nil, parsed_request: nil)
        ctx = context || @context
        return Decision.deny(reason_code: REASON_MERCHANT_REQUIRED, decision_type: :docs_fallback) unless @merchant_id.present?

        Decision.allow(decision_type: :docs_fallback, metadata: {})
      end

      # Expose authorization for record-level checks (tools still use this for allow_record?).
      def authorization
        @auth
      end

      def context
        @context
      end

      def merchant_id
        @merchant_id
      end

      # Safe message for denied access (never leaks record existence).
      def self.denied_message
        Authorization.denied_message
      end

      private

      def wrap_decision(auth_decision, decision_type)
        return auth_decision if auth_decision.respond_to?(:decision_type) && auth_decision.decision_type.present?

        Decision.new(
          allowed: auth_decision.allowed,
          decision_type: decision_type,
          reason_code: auth_decision.reason_code,
          safe_message: auth_decision.safe_message,
          metadata: auth_decision.metadata.to_h
        )
      end

      def ai_debug_enabled?
        ::Ai::Observability::EventLogger.respond_to?(:ai_debug_enabled?) && ::Ai::Observability::EventLogger.ai_debug_enabled?
      end
    end
  end
end
