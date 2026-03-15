# frozen_string_literal: true

module Ai
  module Tools
    # Registry of allowed deterministic tools: name => class, plus optional metadata (ToolDefinition).
    # Single source of truth for tool discovery. All tools must be read_only in current architecture.
    class Registry
      TOOLS = {
        'get_ledger_summary' => Ai::Tools::GetLedgerSummary,
        'get_payment_intent' => Ai::Tools::GetPaymentIntent,
        'get_transaction' => Ai::Tools::GetTransaction,
        'get_webhook_event' => Ai::Tools::GetWebhookEvent,
        'get_merchant_account' => Ai::Tools::GetMerchantAccount
      }.freeze

      DEFINITIONS = {
        'get_ledger_summary' => ToolDefinition.new(
          key: 'get_ledger_summary',
          class_name: 'Ai::Tools::GetLedgerSummary',
          description: 'Returns ledger summary for a merchant and time range.',
          read_only: true,
          requires_merchant_scope: true,
          cacheable: true
        ),
        'get_payment_intent' => ToolDefinition.new(
          key: 'get_payment_intent',
          class_name: 'Ai::Tools::GetPaymentIntent',
          description: 'Returns a single payment intent by ID.',
          read_only: true,
          requires_merchant_scope: true,
          cacheable: false
        ),
        'get_transaction' => ToolDefinition.new(
          key: 'get_transaction',
          class_name: 'Ai::Tools::GetTransaction',
          description: 'Returns a single transaction by ID.',
          read_only: true,
          requires_merchant_scope: true,
          cacheable: false
        ),
        'get_webhook_event' => ToolDefinition.new(
          key: 'get_webhook_event',
          class_name: 'Ai::Tools::GetWebhookEvent',
          description: 'Returns a webhook event by ID.',
          read_only: true,
          requires_merchant_scope: true,
          cacheable: false
        ),
        'get_merchant_account' => ToolDefinition.new(
          key: 'get_merchant_account',
          class_name: 'Ai::Tools::GetMerchantAccount',
          description: 'Returns merchant account metadata.',
          read_only: true,
          requires_merchant_scope: true,
          cacheable: true
        )
      }.freeze

      class << self
        def resolve(tool_name)
          name = tool_name.to_s.strip.downcase
          TOOLS[name.presence]
        end

        def known_tools
          TOOLS.keys
        end

        def known?(tool_name)
          resolve(tool_name).present?
        end

        def definition(tool_name)
          DEFINITIONS[tool_name.to_s.strip.downcase]
        end

        def definitions
          DEFINITIONS.values
        end

        def validate!
          return true unless Rails.env.development? || Rails.env.test?

          seen = []
          TOOLS.each do |name, klass|
            raise ArgumentError, "Tools::Registry: duplicate key #{name.inspect}" if seen.include?(name)
            seen << name
            raise ArgumentError, "Tools::Registry: #{name} class #{klass} not found" unless klass.is_a?(Class)
          end
          raise ArgumentError, "Tools::Registry: DEFINITIONS keys must match TOOLS" if DEFINITIONS.keys.sort != TOOLS.keys.sort
          DEFINITIONS.each do |name, defn|
            raise ArgumentError, "Tools::Registry: #{name} must be read_only" unless defn.read_only?
            raise ArgumentError, "Tools::Registry: #{name} definition missing class_name" if defn.class_name.blank?
          end
          true
        end
      end
    end
  end
end
