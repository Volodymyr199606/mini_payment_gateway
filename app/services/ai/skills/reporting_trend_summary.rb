# frozen_string_literal: true

module Ai
  module Skills
    # Summarizes short-term trends from deterministic ledger outputs.
    # Requires comparative data (current vs previous period). Bounded; no invented trends.
    class ReportingTrendSummary < BaseSkill
      DEFINITION = SkillDefinition.new(
        key: :reporting_trend_summary,
        class_name: 'Ai::Skills::ReportingTrendSummary',
        description: 'Summarize trends from comparative ledger data (current vs previous period).',
        deterministic: true,
        dependencies: %i[tools context],
        input_contract: 'ledger_summary with from/to, optional previous_period totals, merchant_id',
        output_contract: 'SkillResult with trend summary or no-comparison message'
      )

      def execute(context:)
        merchant_id = context[:merchant_id].to_i
        return missing_context unless merchant_id.positive?

        current = resolve_current_ledger(context, merchant_id)
        return no_ledger(context) unless current.present?

        previous = resolve_previous_ledger(context, merchant_id, current)
        unless previous.present?
          return SkillResult.success(
            skill_key: :reporting_trend_summary,
            data: { trend_available: false },
            explanation: '**Trend comparison:** Not enough data to compare two periods yet. Ask for the same length window twice (e.g. last 7 days vs prior 7 days) or a range that includes a clear “previous” interval.',
            metadata: audit_meta(context),
            deterministic: true
          )
        end

        explanation = build_trend_summary(current, previous, context)
        SkillResult.success(
          skill_key: :reporting_trend_summary,
          data: {
            trend_available: true,
            current_totals: current[:totals],
            previous_totals: previous[:totals]
          },
          explanation: explanation,
          metadata: audit_meta(context).merge('trend_computed' => 'true'),
          deterministic: true
        )
      rescue StandardError => e
        SkillResult.failure(
          skill_key: :reporting_trend_summary,
          error_code: 'execution_error',
          error_message: e.message,
          metadata: audit_meta(context)
        )
      end

      private

      def resolve_current_ledger(context, merchant_id)
        ledger = context[:ledger_summary] || context['ledger_summary']
        return normalize_ledger(ledger) if ledger.present?

        from_val, to_val = parse_range(context)
        return nil unless from_val && to_val

        ::Reporting::LedgerSummary.new(
          merchant_id: merchant_id,
          from: from_val,
          to: to_val,
          currency: (context[:currency] || 'USD').to_s.upcase,
          group_by: 'none'
        ).call
      end

      def resolve_previous_ledger(context, merchant_id, current)
        prev = context[:previous_period] || context['previous_period']
        return normalize_ledger(prev) if prev.is_a?(Hash) && prev[:totals].present?

        from_val, to_val = parse_range_from_context(context, current)
        return nil unless from_val && to_val

        duration = to_val - from_val
        prev_to = from_val
        prev_from = prev_to - duration

        ::Reporting::LedgerSummary.new(
          merchant_id: merchant_id,
          from: prev_from,
          to: prev_to,
          currency: (current[:currency] || 'USD').to_s.upcase,
          group_by: 'none'
        ).call
      rescue StandardError
        nil
      end

      def parse_range_from_context(context, current)
        if current[:from].present? && current[:to].present?
          [Time.zone.parse(current[:from].to_s), Time.zone.parse(current[:to].to_s)]
        else
          parse_range(context)
        end
      rescue StandardError
        parse_range(context)
      end

      def normalize_ledger(h)
        h = h.with_indifferent_access if h.respond_to?(:with_indifferent_access)
        {
          totals: h[:totals] || h['totals'] || {},
          currency: h[:currency] || h['currency'] || 'USD',
          from: h[:from] || h['from'],
          to: h[:to] || h['to']
        }.compact
      end

      def parse_range(context)
        preset = (context[:preset] || context['preset']).to_s.strip.downcase.presence || 'last_7_days'
        zone = ActiveSupport::TimeZone['America/Los_Angeles']
        now = zone.now

        case preset
        when 'last_7_days'
          [(now - 7.days).beginning_of_day, now]
        when 'last_week'
          [(now - 1.week).beginning_of_week, (now - 1.week).end_of_week]
        when 'last_month'
          [(now - 1.month).beginning_of_month, (now - 1.month).end_of_month]
        when 'today'
          [now.beginning_of_day, now]
        when 'yesterday'
          d = now - 1.day
          [d.beginning_of_day, d.end_of_day]
        else
          from_s = (context[:from] || context['from']).to_s.strip.presence
          to_s = (context[:to] || context['to']).to_s.strip.presence
          if from_s.present? && to_s.present?
            [Time.zone.parse(from_s), Time.zone.parse(to_s)]
          else
            [(now - 7.days).beginning_of_day, now]
          end
        end
      rescue StandardError
        [nil, nil]
      end

      def build_trend_summary(current, previous, _context)
        ct = (current[:totals] || current['totals'] || {}).with_indifferent_access
        pt = (previous[:totals] || previous['totals'] || {}).with_indifferent_access

        charges_curr = ct[:charges_cents].to_i
        charges_prev = pt[:charges_cents].to_i
        refunds_curr = ct[:refunds_cents].to_i
        refunds_prev = pt[:refunds_cents].to_i
        net_curr = ct[:net_cents].to_i
        net_prev = pt[:net_cents].to_i
        fees_curr = ct[:fees_cents].to_i
        fees_prev = pt[:fees_cents].to_i

        currency = (current[:currency] || 'USD').to_s
        parts = []

        parts << trend_line('Charges', charges_curr, charges_prev, currency)
        parts << trend_line('Refunds', refunds_curr, refunds_prev, currency)
        parts << trend_line('Net', net_curr, net_prev, currency) if net_curr != net_prev || parts.size < 2
        parts << trend_line('Fees', fees_curr, fees_prev, currency) if (fees_curr - fees_prev).abs > 1

        return '**Trend vs previous period:** No meaningful change in charges, refunds, or net between these windows.' if parts.empty?

        "**Trend vs previous period (deterministic):**\n" + parts.compact.join("\n")
      end

      def trend_line(label, curr, prev, currency)
        return nil if prev.zero? && curr.zero?

        diff = curr - prev
        pct = prev.zero? ? (curr.positive? ? 100 : 0) : ((diff.to_f / prev) * 100).round(1)
        dir = diff.positive? ? 'up' : (diff.negative? ? 'down' : 'stable')
        amt = format_cents(diff.abs)
        "#{label}: #{dir} (#{amt} #{currency}, #{pct}%)"
      end

      def format_cents(cents)
        Kernel.format('$%.2f', cents.to_i / 100.0)
      end

      def audit_meta(context)
        { 'agent_key' => context[:agent_key].to_s.presence, 'merchant_id' => context[:merchant_id].to_s.presence }.compact
      end

      def missing_context
        SkillResult.failure(
          skill_key: :reporting_trend_summary,
          error_code: 'missing_context',
          error_message: 'merchant_id required',
          metadata: {}
        )
      end

      def no_ledger(context)
        SkillResult.failure(
          skill_key: :reporting_trend_summary,
          error_code: 'no_ledger_data',
          error_message: 'No ledger summary data or time range provided.',
          metadata: audit_meta(context)
        )
      end
    end
  end
end
