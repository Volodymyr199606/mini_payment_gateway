# frozen_string_literal: true

module Ai
  module Followups
    # Produces effective intent for tools by merging follow-up context with IntentDetector.
    # When Resolver detects a follow-up with inherited entities/time, returns merged intent.
    class IntentResolver
      def self.call(message:, recent_messages: [], merchant_id: nil)
        new(message: message, recent_messages: recent_messages, merchant_id: merchant_id).call
      end

      def initialize(message:, recent_messages: [], merchant_id: nil)
        @message = message.to_s.strip
        @recent = recent_messages
        @merchant_id = merchant_id
      end

      def call
        followup = Resolver.call(current_message: @message, recent_messages: @recent)
        return { intent: nil, followup: followup } if @message.blank?

        # If explicit intent in current message, use it (user overrides)
        current_intent = ::Ai::Tools::IntentDetector.detect(@message)
        return { intent: current_intent, followup: followup } if current_intent

        return { intent: nil, followup: followup } unless followup[:followup_detected]

        # Build intent from inherited context when safe
        resolved = resolve_intent_from_followup(followup)
        { intent: resolved, followup: followup }
      end

      private

      def resolve_intent_from_followup(followup)
        type = followup[:followup_type]
        prior_tool = followup[:prior_intent]
        entities = followup[:inherited_entities] || {}
        time_range = followup[:inherited_time_range]
        @followup_inheritance_blocked = false

        result = case type
        when :entity_followup
          build_entity_intent(prior_tool, entities)
        when :time_range_adjustment
          build_time_intent(prior_tool, time_range)
        when :result_filtering
          build_filter_intent(prior_tool, entities, time_range)
        when :topic_continuation
          build_entity_intent(prior_tool, entities)
        else
          # explanation_rewrite, ambiguous_followup: don't force tool; let agent path handle
          nil
        end
        followup[:followup_inheritance_blocked] = @followup_inheritance_blocked if @followup_inheritance_blocked
        result
      end

      def build_entity_intent(prior_tool, entities)
        return nil if prior_tool.blank? || entities.blank? || @merchant_id.blank?

        engine = ::Ai::Policy::Engine.call(context: { merchant_id: @merchant_id })
        args = entities.stringify_keys

        case prior_tool.to_s
        when 'get_payment_intent'
          pid = args['payment_intent_id']&.to_i
          return nil unless pid.present?
          if engine.allow_followup_inheritance?(inherited_item: { entity_type: 'payment_intent', entity_id: pid }).denied?
            @followup_inheritance_blocked = true
            return nil
          end
          { tool_name: 'get_payment_intent', args: { payment_intent_id: pid } }
        when 'get_transaction'
          if args['processor_ref'].present?
            # processor_ref lookup is done by tool; can't pre-validate
            { tool_name: 'get_transaction', args: { processor_ref: args['processor_ref'] } }
          elsif args['transaction_id'].present?
            tid = args['transaction_id'].to_i
            if engine.allow_followup_inheritance?(inherited_item: { entity_type: 'transaction', entity_id: tid }).denied?
              @followup_inheritance_blocked = true
              return nil
            end
            { tool_name: 'get_transaction', args: { transaction_id: tid } }
          else
            nil
          end
        when 'get_webhook_event'
          wid = args['webhook_event_id']&.to_i
          return nil unless wid.present?
          if engine.allow_followup_inheritance?(inherited_item: { entity_type: 'webhook_event', entity_id: wid }).denied?
            @followup_inheritance_blocked = true
            return nil
          end
          { tool_name: 'get_webhook_event', args: { webhook_event_id: wid } }
        else
          nil
        end
      end

      def build_time_intent(prior_tool, time_range)
        return nil unless time_range && time_range[:from] && time_range[:to]

        # Time adjustments typically apply to reporting
        if prior_tool.to_s == 'get_ledger_summary'
          {
            tool_name: 'get_ledger_summary',
            args: { from: time_range[:from].iso8601, to: time_range[:to].iso8601 }
          }
        else
          nil
        end
      end

      def build_filter_intent(prior_tool, entities, time_range)
        # Filtering: reuse prior tool + entities; filters go to composition metadata
        return build_entity_intent(prior_tool, entities) if entities.present?
        return build_time_intent(prior_tool, time_range) if time_range.present?
        nil
      end
    end
  end
end
