# frozen_string_literal: true

module Ai
  module Skills
    # Rule-based discrepancy detection for reconciliation. Compares ledger,
    # transactions, and payment intent state. Bounded; no autonomous investigation.
    class DiscrepancyDetector < BaseSkill
      DEFINITION = SkillDefinition.new(
        key: :discrepancy_detector,
        class_name: 'Ai::Skills::DiscrepancyDetector',
        description: 'Highlight potential reconciliation discrepancies (rule-based).',
        deterministic: true,
        dependencies: %i[tools context],
        input_contract: 'ledger_summary hash, optional payment_intent_ids or transaction_ids, merchant_id',
        output_contract: 'SkillResult with discrepancy hints or aligned confirmation'
      )

      def execute(context:)
        merchant_id = context[:merchant_id].to_i
        return missing_context_error unless merchant_id.present?

        merchant = Merchant.find_by(id: merchant_id)
        return missing_context_error unless merchant

        findings = []
        ledger = context[:ledger_summary] || fetch_ledger(context, merchant)

        if ledger.present?
          findings.concat(check_ledger_consistency(ledger))
        end

        if context[:payment_intent_id].present? || context[:payment_intent_ids].present?
          ids = Array(context[:payment_intent_id] || context[:payment_intent_ids]).compact.map { |x| x.to_s.strip.presence&.to_i }.compact
          findings.concat(check_payment_intents(merchant, ids))
        end

        if findings.any?
          explanation = "Potential discrepancies:\n" + findings.map { |f| "• #{f}" }.join("\n")
          SkillResult.success(
            skill_key: :discrepancy_detector,
            data: { discrepancies: findings, aligned: false },
            explanation: explanation,
            metadata: audit_metadata(context).merge('aligned' => 'false'),
            deterministic: true
          )
        else
          explanation = ledger.present? ? 'Ledger and payment records appear aligned. No rule-based discrepancies detected.' : 'No ledger or payment intent data provided for discrepancy check.'
          SkillResult.success(
            skill_key: :discrepancy_detector,
            data: { discrepancies: [], aligned: true },
            explanation: explanation,
            metadata: audit_metadata(context).merge('aligned' => 'true'),
            deterministic: true
          )
        end
      rescue StandardError => e
        SkillResult.failure(
          skill_key: :discrepancy_detector,
          error_code: 'execution_error',
          error_message: e.message,
          metadata: audit_metadata(context)
        )
      end

      private

      def fetch_ledger(context, merchant)
        from_val, to_val = parse_range(context)
        return nil unless from_val && to_val

        ::Reporting::LedgerSummary.new(
          merchant_id: merchant.id,
          from: from_val,
          to: to_val,
          currency: (context[:currency] || 'USD').to_s.upcase,
          group_by: 'none'
        ).call
      rescue StandardError
        nil
      end

      def parse_range(context)
        preset = context[:preset].to_s.strip.downcase.presence || 'last_7_days'
        zone = ActiveSupport::TimeZone['America/Los_Angeles']
        now = zone.now
        from, to = case preset
                   when 'all_time' then [Time.zone.parse('2000-01-01'), now]
                   when 'last_7_days' then [(now - 7.days).beginning_of_day, now]
                   when 'last_week' then [(now - 1.week).beginning_of_week, (now - 1.week).end_of_week]
                   when 'last_month' then [(now - 1.month).beginning_of_month, (now - 1.month).end_of_month]
                   when 'today' then [now.beginning_of_day, now]
                   when 'yesterday'
                     d = now - 1.day
                     [d.beginning_of_day, d.end_of_day]
                   else [(now - 7.days).beginning_of_day, now]
                   end
        [from, to]
      end

      def check_ledger_consistency(ledger)
        findings = []
        t = ledger[:totals] || {}
        charges = t[:charges_cents].to_i
        refunds = t[:refunds_cents].to_i

        if refunds > charges
          findings << "Refunds (#{format_cents(refunds)}) exceed charges (#{format_cents(charges)})."
        end

        net = t[:net_cents].to_i
        expected_net = charges - refunds - (t[:fees_cents].to_i)
        if (net - expected_net).abs > 1
          findings << "Net amount (#{format_cents(net)}) does not match expected charges - refunds - fees."
        end

        findings
      end

      def check_payment_intents(merchant, ids)
        findings = []
        ids.each do |pid|
          pi = merchant.payment_intents.find_by(id: pid)
          next unless pi

          if pi.status == 'captured'
            capture_txn = pi.transactions.find_by(kind: 'capture', status: 'succeeded')
            findings << "Payment Intent ##{pi.id} is captured but has no successful capture transaction." if capture_txn.nil?
          elsif pi.status == 'authorized'
            auth_txn = pi.transactions.find_by(kind: 'authorize', status: 'succeeded')
            findings << "Payment Intent ##{pi.id} is authorized but has no successful authorize transaction." if auth_txn.nil?
          end

          if pi.status == 'captured' && pi.respond_to?(:total_refunded_cents)
            captured = pi.transactions.where(kind: 'capture', status: 'succeeded').sum(:amount_cents)
            refunded = pi.total_refunded_cents
            findings << "Payment Intent ##{pi.id}: refunded amount (#{format_cents(refunded)}) exceeds captured (#{format_cents(captured)})." if refunded > captured
          end
        end
        findings
      end

      def format_cents(cents)
        Kernel.format('$%.2f', cents / 100.0)
      end

      def audit_metadata(context)
        {
          'agent_key' => context[:agent_key].to_s.presence,
          'merchant_id' => context[:merchant_id].to_s.presence
        }.compact
      end

      def missing_context_error
        SkillResult.failure(
          skill_key: :discrepancy_detector,
          error_code: 'missing_context',
          error_message: 'merchant_id required',
          metadata: {}
        )
      end
    end
  end
end
