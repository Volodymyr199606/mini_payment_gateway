# frozen_string_literal: true

module Ai
  module Skills
    # Summarizes ledger totals for a time range. Reuses Reporting::LedgerSummary
    # and Ai::Explanations::Renderer. Deterministic.
    class LedgerPeriodSummary < BaseSkill
      DEFINITION = SkillDefinition.new(
        key: :ledger_period_summary,
        class_name: 'Ai::Skills::LedgerPeriodSummary',
        description: 'Summarize ledger for a time period (deterministic tool path).',
        deterministic: true,
        dependencies: %i[tools context],
        input_contract: 'merchant_id, from/to or preset, optional currency',
        output_contract: 'SkillResult with summary text, totals metadata, deterministic'
      )

      PRESETS = %w[all_time last_7_days last_week last_month today yesterday].freeze

      def execute(context:)
        merchant_id = context[:merchant_id].to_i
        return missing_context_error if context[:merchant_id].blank? || merchant_id.zero?

        from_val, to_val = parse_range(context)
        return range_error(context) unless from_val && to_val

        summary = ::Reporting::LedgerSummary.new(
          merchant_id: merchant_id,
          from: from_val,
          to: to_val,
          currency: (context[:currency] || 'USD').to_s.upcase,
          group_by: 'none'
        ).call

        render_and_return(summary, context)
      rescue StandardError => e
        SkillResult.failure(
          skill_key: :ledger_period_summary,
          error_code: 'execution_error',
          error_message: e.message,
          metadata: audit_metadata(context)
        )
      end

      private

      def parse_range(context)
        preset = context[:preset].to_s.strip.downcase.presence
        if preset.present?
          parse_preset(preset)
        else
          from_s = context[:from].to_s.strip.presence
          to_s = context[:to].to_s.strip.presence
          if from_s.present? && to_s.present?
            [Time.zone.parse(from_s), Time.zone.parse(to_s)]
          elsif context[:message].present?
            result = TimeRangeParser.extract_and_parse(context[:message])
            [result[:from], result[:to]]
          else
            [nil, nil]
          end
        end
      end

      def parse_preset(preset)
        zone = ActiveSupport::TimeZone['America/Los_Angeles']
        now = zone.now
        case preset
        when 'all_time' then [Time.zone.parse('2000-01-01 00:00:00'), now]
        when 'last_7_days' then [(now - 7.days).beginning_of_day, now]
        when 'last_week' then [(now - 1.week).beginning_of_week, (now - 1.week).end_of_week]
        when 'last_month' then [(now - 1.month).beginning_of_month, (now - 1.month).end_of_month]
        when 'today' then [now.beginning_of_day, now]
        when 'yesterday'
          d = now - 1.day
          [d.beginning_of_day, d.end_of_day]
        else [nil, nil]
        end
      end

      def render_and_return(summary, context)
        tool_data = summary.merge(totals: summary[:totals] || {}, counts: summary[:counts] || {})
        rendered = Explanations::Renderer.render('get_ledger_summary', tool_data)
        explanation = rendered&.explanation_text || build_fallback_summary(summary)

        SkillResult.success(
          skill_key: :ledger_period_summary,
          data: {
            summary_text: explanation,
            totals: summary[:totals],
            counts: summary[:counts],
            from: summary[:from],
            to: summary[:to],
            currency: summary[:currency]
          },
          explanation: explanation,
          metadata: audit_metadata(context).merge(
            'explanation_type' => 'ledger_summary',
            'from' => summary[:from].to_s[0, 10],
            'to' => summary[:to].to_s[0, 10]
          ),
          deterministic: true
        )
      end

      def build_fallback_summary(summary)
        t = summary[:totals] || {}
        c = summary[:counts] || {}
        charges = format_money((t[:charges_cents].to_i) / 100.0)
        refunds = format_money((t[:refunds_cents].to_i) / 100.0)
        fees = format_money((t[:fees_cents].to_i) / 100.0)
        net = format_money((t[:net_cents].to_i) / 100.0)
        currency = (summary[:currency] || 'USD').to_s
        from_s = summary[:from].to_s[0, 10]
        to_s = summary[:to].to_s[0, 10]
        "**Here's your ledger** (#{from_s}–#{to_s}): **Charges** #{charges}; **Refunds** #{refunds}; **Fees** #{fees}; **Net** #{net} #{currency}. " \
          "(#{c[:captures_count].to_i} captures, #{c[:refunds_count].to_i} refunds in range.)"
      end

      def format_money(amount)
        Kernel.format('$%.2f', amount.to_f)
      end

      def audit_metadata(context)
        {
          'agent_key' => context[:agent_key].to_s.presence,
          'merchant_id' => context[:merchant_id].to_s.presence
        }.compact
      end

      def missing_context_error
        SkillResult.failure(
          skill_key: :ledger_period_summary,
          error_code: 'missing_context',
          error_message: 'merchant_id required',
          metadata: {}
        )
      end

      def range_error(context)
        SkillResult.failure(
          skill_key: :ledger_period_summary,
          error_code: 'missing_range',
          error_message: 'Provide from/to, preset, or message with time phrase. Presets: ' + PRESETS.join(', '),
          metadata: audit_metadata(context)
        )
      end
    end
  end
end
