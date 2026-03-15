# frozen_string_literal: true

module Ai
  module Explanations
    # Renders deterministic explanation from tool name + data using TemplateRegistry.
    class Renderer
      def self.render(tool_name, data)
        new(tool_name: tool_name, data: data).render
      end

      def initialize(tool_name:, data:)
        @tool_name = tool_name.to_s.strip
        @data = data.is_a?(Hash) ? data.deep_symbolize_keys : {}
      end

      def render
        key = TemplateRegistry.select_key(@tool_name, @data)
        return nil unless key.present?

        template = find_template(key)
        return nil unless template.present?

        bindings = build_bindings(key)
        text = interpolate(template, bindings)
        explanation_type = @tool_name.sub(/\Aget_/, '')
        RenderedExplanation.for_tool(
          explanation_text: text,
          explanation_type: explanation_type,
          explanation_key: key,
          metadata: { tool_name: @tool_name }
        )
      end

      private

      def find_template(key)
        case @tool_name
        when 'get_payment_intent' then TemplateRegistry::PAYMENT_INTENT[key]
        when 'get_transaction' then TemplateRegistry::TRANSACTION[key]
        when 'get_webhook_event' then TemplateRegistry::WEBHOOK[key]
        when 'get_ledger_summary' then TemplateRegistry::LEDGER[key]
        when 'get_merchant_account' then TemplateRegistry::MERCHANT_ACCOUNT[key]
        else nil
        end
      end

      def build_bindings(key)
        case @tool_name
        when 'get_payment_intent' then bind_payment_intent
        when 'get_transaction' then bind_transaction
        when 'get_webhook_event' then bind_webhook
        when 'get_ledger_summary' then bind_ledger
        when 'get_merchant_account' then bind_merchant_account
        else {}
        end
      end

      def bind_payment_intent
        cents = @data[:amount_cents].to_i
        {
          id: @data[:id],
          amount: format_money(cents / 100.0),
          currency: @data[:currency].to_s.upcase.presence || 'USD'
        }
      end

      def bind_transaction
        cents = @data[:amount_cents].to_i
        {
          id: @data[:id],
          kind: @data[:kind],
          status: @data[:status],
          amount: format_money(cents / 100.0),
          processor_ref: @data[:processor_ref].present? ? @data[:processor_ref] : '—'
        }
      end

      def bind_webhook
        {
          id: @data[:id],
          event_type: @data[:event_type],
          delivery_status: @data[:delivery_status],
          attempts: @data[:attempts].to_i
        }
      end

      def bind_ledger
        t = @data[:totals] || {}
        c = @data[:counts] || {}
        entries = c[:captures_count].to_i + c[:refunds_count].to_i
        {
          from: @data[:from].to_s[0, 10],
          to: @data[:to].to_s[0, 10],
          charges: format_money((t[:charges_cents].to_i) / 100.0),
          refunds: format_money((t[:refunds_cents].to_i) / 100.0),
          fees: format_money((t[:fees_cents].to_i) / 100.0),
          net: format_money((t[:net_cents].to_i) / 100.0),
          currency: (@data[:currency] || 'USD').to_s.upcase,
          entries_count: entries
        }
      end

      def bind_merchant_account
        {
          id: @data[:id],
          name: @data[:name].to_s.presence || 'Account',
          status: @data[:status],
          payment_intents_count: @data[:payment_intents_count].to_i,
          webhook_events_count: @data[:webhook_events_count].to_i
        }
      end

      def interpolate(template, bindings)
        return template if bindings.blank?

        bindings.reduce(template) do |str, (k, v)|
          str.gsub(/\{\{#{k}\}\}/, v.to_s)
        end
      end

      def format_money(amount)
        Kernel.format('$%.2f', amount.to_f)
      end
    end
  end
end
