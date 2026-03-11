# frozen_string_literal: true

module Ai
  module Tools
    # Registry of allowed deterministic tools. Maps tool names to service classes.
    # Read-only, no side effects, no external calls.
    class Registry
      TOOLS = {
        'get_ledger_summary' => Ai::Tools::GetLedgerSummary,
        'get_payment_intent' => Ai::Tools::GetPaymentIntent,
        'get_transaction' => Ai::Tools::GetTransaction,
        'get_webhook_event' => Ai::Tools::GetWebhookEvent,
        'get_merchant_account' => Ai::Tools::GetMerchantAccount
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
      end
    end
  end
end
