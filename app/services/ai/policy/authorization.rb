# frozen_string_literal: true

module Ai
  module Policy
    # Centralized merchant-scoped AI authorization. All AI data access flows through here.
    # Ensures deterministic product/account data never crosses tenant boundaries.
    class Authorization
      REASON_MERCHANT_REQUIRED = 'merchant_required'
      REASON_RECORD_NOT_OWNED = 'record_not_owned'
      REASON_RECORD_NOT_FOUND = 'record_not_found'
      REASON_ENTITY_INVALID = 'entity_invalid'
      REASON_FOLLOWUP_UNSAFE = 'followup_inheritance_unsafe'
      REASON_TOOL_NOT_ALLOWED = 'tool_not_allowed'

      def self.call(context:)
        new(context: context)
      end

      def initialize(context:)
        @ctx = context.to_h.stringify_keys
        @merchant_id = @ctx['merchant_id']&.to_i
      end

      # Whether a tool may run for the current context.
      def allow_tool?(tool_name:, args: {})
        return Decision.deny(reason_code: REASON_MERCHANT_REQUIRED) unless @merchant_id.present?

        unless ::Ai::Tools::Registry.known?(tool_name)
          return Decision.deny(reason_code: REASON_TOOL_NOT_ALLOWED, metadata: { tool_name: tool_name.to_s })
        end

        # Ledger and merchant_account are inherently scoped by merchant_id in args/context.
        # Entity tools (payment_intent, transaction, webhook) validate via allow_record? after fetch.
        Decision.allow(metadata: { tool_name: tool_name.to_s })
      end

      # Generic safe error message for denied access. Never leaks record existence.
      def self.denied_message
        'Could not fetch data.'
      end

      # Whether a fetched record may be returned to the caller. Validates ownership.
      def allow_record?(record:, record_type: nil)
        return Decision.deny(reason_code: REASON_RECORD_NOT_FOUND) if record.nil?
        return Decision.deny(reason_code: REASON_MERCHANT_REQUIRED) unless @merchant_id.present?

        owner_id = record_owner_id(record, record_type)
        return Decision.deny(reason_code: REASON_RECORD_NOT_OWNED) if owner_id.nil?
        if owner_id != @merchant_id
          return Decision.deny(
            reason_code: REASON_RECORD_NOT_OWNED,
            metadata: { record_type: record_type || record.class.name }
          )
        end

        Decision.allow
      end

      # Whether an entity reference (id lookup) is safe before running a tool.
      def allow_entity_reference?(entity_type:, entity_id:, args: {})
        return Decision.deny(reason_code: REASON_MERCHANT_REQUIRED) unless @merchant_id.present?
        return Decision.deny(reason_code: REASON_ENTITY_INVALID) if entity_id.blank?

        exists_and_owned = case entity_type.to_s
        when 'payment_intent'
          PaymentIntent.where(merchant_id: @merchant_id).exists?(id: entity_id.to_i)
        when 'transaction'
          Transaction.joins(:payment_intent).where(payment_intents: { merchant_id: @merchant_id }).exists?(id: entity_id.to_i)
        when 'webhook_event'
          WebhookEvent.where(merchant_id: @merchant_id).exists?(id: entity_id.to_i)
        else
          false
        end

        return Decision.deny(reason_code: REASON_RECORD_NOT_OWNED) unless exists_and_owned

        Decision.allow
      end

      # Whether inherited entity from follow-up may be reused. Revalidates ownership.
      def allow_followup_inheritance?(entity_type:, entity_id:, **)
        allow_entity_reference?(entity_type: entity_type, entity_id: entity_id)
      end

      # Whether composed/merged data from orchestration may be returned.
      def allow_composed_data?(source_type:, data: nil)
        return Decision.deny(reason_code: REASON_MERCHANT_REQUIRED) unless @merchant_id.present?

        return Decision.allow unless data.is_a?(Hash)

        # Validate nested records if present
        if data[:payment_intent].is_a?(Hash) && data[:payment_intent][:merchant_id].present?
          return Decision.deny(reason_code: REASON_RECORD_NOT_OWNED) if data[:payment_intent][:merchant_id] != @merchant_id
        end
        if data[:transaction].is_a?(Hash)
          pi_id = data[:transaction][:payment_intent_id]
          if pi_id.present?
            return Decision.deny(reason_code: REASON_RECORD_NOT_OWNED) unless PaymentIntent.where(merchant_id: @merchant_id).exists?(id: pi_id)
          end
        end

        Decision.allow
      end

      def context
        @ctx
      end

      def merchant_id
        @merchant_id
      end

      private

      def record_owner_id(record, record_type)
        case record
        when PaymentIntent, WebhookEvent
          record.merchant_id
        when Merchant
          record.id # Must equal context merchant_id
        when Transaction
          record.payment_intent&.merchant_id
        else
          record.respond_to?(:merchant_id) ? record.merchant_id : nil
        end
      end
    end
  end
end
