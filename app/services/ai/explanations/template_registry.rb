# frozen_string_literal: true

module Ai
  module Explanations
    # Maps tool name + data to explanation template keys and holds template strings.
    # All templates are deterministic and human-readable.
    class TemplateRegistry
      PAYMENT_INTENT = {
        'created' => 'Payment intent #{{id}} is in **created** status. Amount: {{amount}} {{currency}}. It has not been authorized yet.',
        'authorized' => 'Payment intent #{{id}} is **authorized**. Amount: {{amount}} {{currency}}. It is ready to capture.',
        'requires_capture' => 'Payment intent #{{id}} is authorized and **requires capture**. Amount: {{amount}} {{currency}}. Capture it to settle the funds.',
        'captured' => 'Payment intent #{{id}} is **captured**. Amount: {{amount}} {{currency}}. The funds have been settled.',
        'canceled' => 'Payment intent #{{id}} has been **canceled** (voided). No charge was made.',
        'failed' => 'Payment intent #{{id}} **failed**. It did not reach a successful authorization or capture.',
        'refunded' => 'Payment intent #{{id}} is captured and has been **refunded** (fully or partially).',
        'disputed_none' => 'Payment intent #{{id}}: dispute status is **none**. No open dispute.',
        'disputed_open' => 'Payment intent #{{id}} has an **open dispute**. Review and respond to the dispute.'
      }.freeze

      TRANSACTION = {
        'authorize_succeeded' => 'Transaction #{{id}} (**authorize**) **succeeded**. Amount: {{amount}}. Status: {{status}}. Processor ref: {{processor_ref}}.',
        'capture_succeeded' => 'Transaction #{{id}} (**capture**) **succeeded**. Amount: {{amount}}. Status: {{status}}. Processor ref: {{processor_ref}}.',
        'refund_succeeded' => 'Transaction #{{id}} (**refund**) **succeeded**. Amount: {{amount}}. Status: {{status}}. Processor ref: {{processor_ref}}.',
        'void_succeeded' => 'Transaction #{{id}} (**void**) **succeeded**. The authorization was voided. Processor ref: {{processor_ref}}.',
        'transaction_failed' => 'Transaction #{{id}} ({{kind}}) **failed**. Status: {{status}}.',
        'transaction_succeeded' => 'Transaction #{{id}} ({{kind}}): **succeeded**. Amount: {{amount}}. Status: {{status}}. Processor ref: {{processor_ref}}.'
      }.freeze

      WEBHOOK = {
        'received' => 'Webhook event #{{id}}: **{{event_type}}**. Delivery status: {{delivery_status}}. Attempts: {{attempts}}.',
        'delivery_pending' => 'Webhook event #{{id}} ({{event_type}}) has been **received**. Delivery is **pending** ({{attempts}} attempt(s)).',
        'delivery_succeeded' => 'Webhook event #{{id}} ({{event_type}}) was **delivered successfully**. Attempts: {{attempts}}.',
        'delivery_failed' => 'Webhook event #{{id}} ({{event_type}}) **delivery failed** after {{attempts}} attempt(s). It may be retried.'
      }.freeze

      LEDGER = {
        'summary' => '**Ledger summary** ({{from}} to {{to}}): Charges: {{charges}}; Refunds: {{refunds}}; Fees: {{fees}}; **Net: {{net}}** {{currency}}. ({{entries_count}} entries in range.)'
      }.freeze

      MERCHANT_ACCOUNT = {
        'account_summary' => '**Account**: {{name}} (#{{id}}). Status: **{{status}}**. Payment intents: {{payment_intents_count}}; Webhook events: {{webhook_events_count}}.'
      }.freeze

      class << self
        # Returns template key for the given tool result, or nil if no template applies.
        def select_key(tool_name, data)
          return nil if data.blank? || !data.is_a?(Hash)

          case tool_name.to_s
          when 'get_payment_intent'
            select_payment_intent_key(data)
          when 'get_transaction'
            select_transaction_key(data)
          when 'get_webhook_event'
            select_webhook_key(data)
          when 'get_ledger_summary'
            'summary'
          when 'get_merchant_account'
            'account_summary'
          else
            nil
          end
        end

        def template_for(key, category: nil)
          h = category ? send(category) : all_templates
          h[key.to_s]
        end

        def all_templates
          PAYMENT_INTENT.merge(TRANSACTION).merge(WEBHOOK).merge(LEDGER).merge(MERCHANT_ACCOUNT)
        end

        private

        def select_payment_intent_key(data)
          status = (data[:status] || data['status']).to_s
          dispute = (data[:dispute_status] || data['dispute_status']).to_s

          return "disputed_#{dispute}" if dispute == 'open'
          return 'disputed_none' if dispute.present? && dispute != 'open'

          case status
          when 'created' then 'created'
          when 'authorized' then 'authorized'
          when 'requires_capture' then 'requires_capture'
          when 'captured' then 'captured'
          when 'canceled' then 'canceled'
          when 'failed' then 'failed'
          else 'created' # fallback
          end
        end

        def select_transaction_key(data)
          kind = (data[:kind] || data['kind']).to_s.downcase
          status = (data[:status] || data['status']).to_s.downcase
          succeeded = status == 'succeeded'

          return 'transaction_failed' unless succeeded
          case kind
          when 'authorize' then 'authorize_succeeded'
          when 'capture' then 'capture_succeeded'
          when 'refund' then 'refund_succeeded'
          when 'void' then 'void_succeeded'
          else 'transaction_succeeded'
          end
        end

        def select_webhook_key(data)
          delivery = (data[:delivery_status] || data['delivery_status']).to_s.downcase
          case delivery
          when 'pending' then 'delivery_pending'
          when 'succeeded' then 'delivery_succeeded'
          when 'failed' then 'delivery_failed'
          else 'received'
          end
        end
      end
    end
  end
end
