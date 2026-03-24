# frozen_string_literal: true

module Ai
  module Skills
    # Immutable context passed to InvocationPlanner for skill selection.
    # Holds phase-relevant request and execution state. Safe for audit.
    class InvocationContext
      PHASES = %i[pre_retrieval pre_tool post_tool pre_composition].freeze

      attr_reader :phase, :agent_key, :merchant_id, :message,
                  :tool_names, :tool_result, :deterministic_data,
                  :run_result, :execution_plan, :followup,
                  :prior_assistant_content, :intent

      def initialize(
        phase:,
        agent_key: nil,
        merchant_id: nil,
        message: nil,
        tool_names: [],
        tool_result: nil,
        deterministic_data: nil,
        run_result: nil,
        execution_plan: nil,
        followup: nil,
        prior_assistant_content: nil,
        intent: nil
      )
        @phase = phase.to_sym
        @agent_key = (agent_key || infer_agent_from_tool).to_s.to_sym
        @merchant_id = merchant_id
        @message = message.to_s.strip.presence
        @tool_names = Array(tool_names).map(&:to_s)
        @tool_result = tool_result
        @deterministic_data = deterministic_data.is_a?(Hash) ? deterministic_data : {}
        @run_result = run_result
        @execution_plan = execution_plan
        @followup = followup.is_a?(Hash) ? followup : {}
        @prior_assistant_content = prior_assistant_content.to_s.strip.presence
        @intent = intent
      end

      def self.for_pre_retrieval(agent_key:, merchant_id:, message:)
        new(phase: :pre_retrieval, agent_key: agent_key, merchant_id: merchant_id, message: message)
      end

      def self.for_pre_tool(agent_key:, merchant_id:, message:, intent: nil)
        new(phase: :pre_tool, agent_key: agent_key, merchant_id: merchant_id, message: message, intent: intent)
      end

      def self.for_pre_composition(agent_key:, merchant_id:, message:, followup:, prior_assistant_content:, execution_plan: nil)
        new(
          phase: :pre_composition,
          agent_key: agent_key,
          merchant_id: merchant_id,
          message: message,
          followup: followup,
          prior_assistant_content: prior_assistant_content,
          execution_plan: execution_plan
        )
      end

      def self.for_post_tool(agent_key:, merchant_id:, message:, tool_names:, deterministic_data:, run_result: nil, intent: nil)
        new(
          phase: :post_tool,
          agent_key: agent_key,
          merchant_id: merchant_id,
          message: message,
          tool_names: tool_names,
          deterministic_data: deterministic_data || {},
          run_result: run_result,
          intent: intent
        )
      end

      def followup_rewrite?
        @followup[:followup_type] == :explanation_rewrite
      end

      def concise_rewrite_mode?
        @execution_plan&.execution_mode == :concise_rewrite_only
      end

      def has_payment_data?
        @tool_names.include?('get_payment_intent') || @tool_names.include?('get_transaction') ||
          extract_entity(:payment_intent).present? || extract_entity(:transaction).present?
      end

      def has_payment_intent_data?
        @tool_names.include?('get_payment_intent') || extract_entity(:payment_intent).present?
      end

      def captured_payment_intent_with_refund_context?
        pi = extract_entity(:payment_intent) || (@tool_names.include?('get_payment_intent') ? @deterministic_data : nil)
        return false unless pi.is_a?(Hash)

        status = (pi[:status] || pi['status']).to_s
        status == 'captured'
      end

      def authorization_vs_capture_message?
        msg = @message.to_s.downcase
        msg.match?(/\b(authorization|authorised|capture|settle|hold)\b/) ||
          msg.include?('authorized vs') || msg.include?('auth vs capture')
      end

      def refund_eligibility_message?
        @message.to_s.match?(/\b(refund|refundable|remaining|partial refund)\b/i)
      end

      def has_webhook_data?
        @tool_names.include?('get_webhook_event') || extract_entity(:webhook_event).present?
      end

      def has_ledger_data?
        @tool_names.include?('get_ledger_summary') || extract_entity(:ledger_summary).present?
      end

      def has_payment_failure_data?
        return false unless has_payment_data?

        pi = extract_entity(:payment_intent) || (primary_tool == 'get_payment_intent' ? @deterministic_data : nil)
        txn = extract_entity(:transaction) || (primary_tool == 'get_transaction' ? @deterministic_data : nil)
        return true if pi.present? && %w[failed canceled].include?((pi[:status] || pi['status']).to_s)
        return true if txn.present? && (txn[:status] || txn['status']).to_s.downcase != 'succeeded'

        false
      end

      # Webhook retry summary is most relevant when delivery is pending or failed.
      def has_webhook_retry_relevant_state?
        return false unless has_webhook_data?

        webhook = extract_entity(:webhook_event) || (primary_tool == 'get_webhook_event' ? @deterministic_data : nil)
        return false unless webhook.is_a?(Hash)

        status = (webhook[:delivery_status] || webhook['delivery_status']).to_s.downcase
        %w[pending failed].include?(status)
      end

      # Message suggests trend/compare/previous-period interest.
      def has_trend_context?
        return false if @message.blank?

        @message.match?(/\b(trend|compare|vs|versus|previous|prior|last\s+week|this\s+week|up|down|change)\b/i)
      end

      def extract_entity(key)
        data = @deterministic_data || {}
        data[key] || data[key.to_s]
      end

      def primary_tool
        @tool_names.first
      end

      def to_skill_context
        base = {
          merchant_id: @merchant_id,
          message: @message,
          agent_key: @agent_key
        }
        case @phase
        when :pre_composition
          base.merge(
            prior_assistant_content: @prior_assistant_content,
            response_style: @followup[:response_style_adjustments],
            response_style_adjustments: @followup[:response_style_adjustments]
          )
        when :post_tool
          data = @deterministic_data || {}
          pi = extract_entity(:payment_intent) || (primary_tool == 'get_payment_intent' && data.present? ? data : nil)
          txn = extract_entity(:transaction) || (primary_tool == 'get_transaction' && data.present? ? data : nil)
          webhook = extract_entity(:webhook_event) || (primary_tool == 'get_webhook_event' && data.present? ? data : nil)
          ledger = extract_entity(:ledger_summary) || (primary_tool == 'get_ledger_summary' && data.present? ? data : nil)
          preset = (data[:preset] || data['preset'] || intent&.dig(:preset)).to_s.presence
          base.merge(
            payment_intent_id: pi&.dig(:id) || pi&.dig('id'),
            payment_intent: pi,
            transaction_id: txn&.dig(:id) || txn&.dig('id'),
            transaction: txn,
            webhook_event_id: webhook&.dig(:id) || webhook&.dig('id'),
            webhook_event: webhook,
            ledger_summary: ledger,
            preset: preset,
            from: ledger&.dig(:from) || ledger&.dig('from'),
            to: ledger&.dig(:to) || ledger&.dig('to')
          )
        else
          base
        end.compact
      end

      private

      def infer_agent_from_tool
        return nil unless primary_tool.present?

        case primary_tool.to_s
        when 'get_ledger_summary' then :reporting_calculation
        when 'get_webhook_event' then :operational
        when 'get_payment_intent', 'get_transaction' then :operational
        else :support_faq
        end
      end
    end
  end
end
