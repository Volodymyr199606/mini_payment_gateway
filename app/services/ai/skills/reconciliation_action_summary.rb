# frozen_string_literal: true

module Ai
  module Skills
    # Produces bounded next-step guidance for reconciliation and discrepancy follow-up.
    # Non-autonomous; suggests what to inspect based on ledger state. Safe for audit.
    class ReconciliationActionSummary < BaseSkill
      DEFINITION = SkillDefinition.new(
        key: :reconciliation_action_summary,
        class_name: 'Ai::Skills::ReconciliationActionSummary',
        description: 'Suggest next steps for reconciliation and discrepancy follow-up.',
        deterministic: true,
        dependencies: %i[tools context],
        input_contract: 'ledger_summary hash, optional discrepancy hints, merchant_id',
        output_contract: 'SkillResult with bounded next-step guidance'
      )

      def execute(context:)
        merchant_id = context[:merchant_id].to_i
        return missing_context unless merchant_id.positive?

        ledger = resolve_ledger(context, merchant_id)
        findings = ledger.present? ? check_consistency(ledger) : []

        actions = build_actions(findings, ledger)
        explanation = "**Suggested next steps (bounded):**\n" + actions.map { |a| "• #{a}" }.join("\n")

        SkillResult.success(
          skill_key: :reconciliation_action_summary,
          data: { actions: actions, has_discrepancies: findings.any? },
          explanation: explanation,
          metadata: audit_meta(context).merge('action_count' => actions.size),
          deterministic: true
        )
      rescue StandardError => e
        SkillResult.failure(
          skill_key: :reconciliation_action_summary,
          error_code: 'execution_error',
          error_message: e.message,
          metadata: audit_meta(context)
        )
      end

      private

      def resolve_ledger(context, merchant_id)
        ledger = context[:ledger_summary] || context['ledger_summary']
        return ledger if ledger.present? && ledger.is_a?(Hash)

        from_val, to_val = parse_range(context)
        return nil unless from_val && to_val

        ::Reporting::LedgerSummary.new(
          merchant_id: merchant_id,
          from: from_val,
          to: to_val,
          currency: (context[:currency] || 'USD').to_s.upcase,
          group_by: 'none'
        ).call
      rescue StandardError
        nil
      end

      def parse_range(context)
        preset = (context[:preset] || context['preset']).to_s.strip.downcase.presence || 'last_7_days'
        zone = ActiveSupport::TimeZone['America/Los_Angeles']
        now = zone.now

        case preset
        when 'last_7_days' then [(now - 7.days).beginning_of_day, now]
        when 'last_week' then [(now - 1.week).beginning_of_week, (now - 1.week).end_of_week]
        when 'last_month' then [(now - 1.month).beginning_of_month, (now - 1.month).end_of_month]
        when 'today' then [now.beginning_of_day, now]
        when 'yesterday'
          d = now - 1.day
          [d.beginning_of_day, d.end_of_day]
        else
          from_s = (context[:from] || context['from']).to_s.strip.presence
          to_s = (context[:to] || context['to']).to_s.strip.presence
          from_s.present? && to_s.present? ? [Time.zone.parse(from_s), Time.zone.parse(to_s)] : [nil, nil]
        end
      end

      def check_consistency(ledger)
        findings = []
        t = (ledger[:totals] || ledger['totals'] || {}).with_indifferent_access
        charges = t[:charges_cents].to_i
        refunds = t[:refunds_cents].to_i
        net = t[:net_cents].to_i
        fees = t[:fees_cents].to_i

        findings << :refunds_exceed_charges if refunds > charges
        expected_net = charges - refunds - fees
        findings << :net_mismatch if (net - expected_net).abs > 1

        findings
      end

      def build_actions(findings, _ledger)
        actions = []

        if findings.include?(:refunds_exceed_charges)
          actions << 'Open the Transactions view and filter refunds in this period; confirm each refund ties to a captured charge.'
          actions << 'Compare refund totals against captured amount per payment intent.'
        end

        if findings.include?(:net_mismatch)
          actions << 'Re-export or compare ledger line items vs. payment and refund transactions for the same dates.'
          actions << 'Confirm fees and currency match what you expect in reporting settings.'
        end

        actions << 'Spot-check a few payment intents: status (authorized / captured / refunded) should match ledger movements.' if actions.empty?
        actions << 'Check for failed or pending transactions that may not yet appear on the ledger.' if actions.size < 3
        actions << 'If webhooks drive your books, confirm recent events for this period were delivered.' if actions.size < 4

        actions.uniq.first(5)
      end

      def audit_meta(context)
        { 'agent_key' => context[:agent_key].to_s.presence, 'merchant_id' => context[:merchant_id].to_s.presence }.compact
      end

      def missing_context
        SkillResult.failure(
          skill_key: :reconciliation_action_summary,
          error_code: 'missing_context',
          error_message: 'merchant_id required',
          metadata: {}
        )
      end
    end
  end
end
