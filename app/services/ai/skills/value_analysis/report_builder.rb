# frozen_string_literal: true

module Ai
  module Skills
    module ValueAnalysis
      # Builds a structured hash + markdown summary for skill value evidence.
      # Combines audit-based metrics (when data exists) with static eval coverage from YAML fixtures.
      class ReportBuilder
        # @param audit_scope [ActiveRecord::Relation, nil] scope for AiRequestAudit; nil uses all rows
        # @param eval_results [Array<Hash>, nil] optional batch eval results for pass-rate overlay
        def self.build(audit_scope: nil, eval_results: nil)
          new(audit_scope: audit_scope, eval_results: eval_results).build
        end

        def initialize(audit_scope:, eval_results:)
          @audit_scope = audit_scope || AiRequestAudit.all
          @eval_results = eval_results
        end

        def build
          metrics = MetricCalculator.call(scope: @audit_scope)
          coverage = ScenarioScorecard.coverage_from_fixtures
          scorecard_summary = ScenarioScorecard.summary
          eval_pass = @eval_results.present? ? ScenarioScorecard.eval_pass_rates_by_scenario(@eval_results) : {}

          static = static_registry_signals
          rankings = derive_rankings(metrics, coverage, static)

          {
            generated_at: Time.zone.now.iso8601,
            audit_scope_description: scope_description,
            metrics: metrics,
            scenario_coverage: coverage,
            scenario_scorecard_summary: scorecard_summary,
            eval_pass_by_scenario: eval_pass.presence,
            static: static,
            rankings: rankings,
            markdown: render_markdown(metrics, coverage, scorecard_summary, static, eval_pass, rankings)
          }
        end

        private

        def scope_description
          return 'AiRequestAudit.all' unless @audit_scope.respond_to?(:where_values_hash)

          hv = @audit_scope.where_values_hash
          hv.present? ? hv.inspect : 'AiRequestAudit (unscoped relation)'
        end

        def static_registry_signals
          skills = Ai::Skills::Registry::SKILLS.keys.sort
          deterministic_flags = skills.each_with_object({}) do |k, h|
            defn = Ai::Skills::Registry.definition(k)
            h[k.to_s] = defn&.deterministic? ? true : false
          rescue StandardError
            h[k.to_s] = nil
          end

          workflows = Ai::Skills::Workflows::Registry.keys

          {
            registered_skill_keys: skills.map(&:to_s),
            skill_definition_deterministic: deterministic_flags,
            registered_workflow_keys: workflows.map(&:to_s)
          }
        end

        def derive_rankings(metrics, coverage, static)
          by_skill = metrics[:by_skill] || {}
          has_audits = metrics[:audit_sample_size].to_i.positive?

          skill_entries = static[:registered_skill_keys].map do |sk|
            cov = coverage[sk] || { scenario_count: 0, scenario_ids: [] }
            m = by_skill[sk]
            inv = m&.dig(:invocation_count).to_i
            aff = m&.dig(:affected_rate).to_f
            det = m&.dig(:deterministic_rate).to_f

            evidence = []
            evidence << 'eval_fixtures' if cov[:scenario_count].to_i.positive?
            evidence << 'production_audits' if has_audits && inv.positive?

            prod_signal = if has_audits && inv.positive?
                            (aff * Math.log(inv + 1)).round(4)
                          end

            {
              skill_key: sk,
              eval_scenario_count: cov[:scenario_count].to_i,
              production_invocation_count: inv,
              production_affected_rate: m&.dig(:affected_rate),
              production_deterministic_rate: m&.dig(:deterministic_rate),
              production_signal_score: prod_signal,
              evidence_sources: evidence
            }
          end

          by_eval = skill_entries.sort_by { |e| -e[:eval_scenario_count] }
          by_prod = skill_entries.select { |e| e[:production_signal_score].present? }
                                 .sort_by { |e| -e[:production_signal_score].to_f }

          {
            by_eval_scenario_coverage: by_eval,
            by_production_signal: by_prod,
            notes: [
              'Rankings are evidence helpers, not revenue or user-satisfaction scores.',
              'production_signal_score = affected_rate * ln(invocation_count + 1) when audits exist.',
              'Skills with eval coverage but zero production data are still engineering-validated.'
            ]
          }
        end

        def render_markdown(metrics, coverage, scorecard_summary, static, eval_pass, rankings)
          lines = []
          lines << '# AI skill value — evidence snapshot'
          lines << ''
          lines << "Generated: `#{Time.zone.now.iso8601}`"
          lines << ''
          lines << '## What this measures'
          lines << '- **Audit metrics**: frequencies and `affected_final_response` / deterministic flags from `ai_request_audits` (production or any scope you pass).'
          lines << '- **Eval coverage**: how many checked-in YAML scenarios expect each skill (contract/regression intent).'
          lines << '- **Registry**: which skills are registered and which workflows exist (design intent).'
          lines << '- This does **not** estimate revenue, NPS, or semantic “quality” — only observable signals.'
          lines << ''

          lines << '## Audit sample'
          lines << "- Rows: **#{metrics[:audit_sample_size]}**"
          if metrics[:audit_sample_size].to_i.positive?
            lines << "- Requests with any skill: **#{metrics[:requests_with_any_skill]}** (#{(metrics[:requests_with_any_skill_rate].to_f * 100).round(1)}%)"
            lines << "- Requests where a skill affected the reply: **#{metrics[:requests_with_skill_affected_response]}** (#{(metrics[:skill_affected_request_rate].to_f * 100).round(1)}%)"
            lines << "- Skill invocations (total rows): **#{metrics[:skill_invocation_total]}**; deterministic share: **#{(metrics[:skill_invocation_deterministic_rate].to_f * 100).round(1)}%**"
            lines << "- deterministic_explanation_used ∧ skill: **#{metrics[:deterministic_explanation_with_any_skill]}** (#{(metrics[:deterministic_explanation_with_skill_rate].to_f * 100).round(1)}% of requests with skills)"
            lines << ''
            lines << '### Workflow keys (audit metadata)'
            if metrics[:workflow_key_frequency].present?
              metrics[:workflow_key_frequency].each { |k, v| lines << "- `#{k}`: #{v}" }
            else
              lines << '- (none in scope)'
            end
            lines << ''
            lines << '### Per-skill (production signals in scope)'
            metrics[:by_skill].sort_by { |k, _| k }.each do |sk, row|
              lines << "- **#{sk}**: invocations=#{row[:invocation_count]}, affected_rate=#{row[:affected_rate]}, deterministic_rate=#{row[:deterministic_rate]}"
            end
            lines << ''
            lines << '### Skill mix by `agent_key` on audit row'
            (metrics[:skill_invocations_by_audit_agent] || {}).sort_by { |k, _| k }.each do |agent, skills|
              lines << "- **#{agent}**: #{skills.map { |sk, n| "#{sk}=#{n}" }.join(', ')}"
            end
          else
            lines << '_No rows in scope — run against a DB with audit data, or rely on eval coverage below._'
          end
          lines << ''

          lines << '## Eval / regression coverage (fixtures)'
          lines << "- Fixture files resolved: **#{scorecard_summary[:fixture_paths_resolved]}** / #{ScenarioScorecard::DEFAULT_FIXTURES.size}"
          lines << "- Distinct skills referenced in expectations: **#{scorecard_summary[:skills_covered]&.size || 0}**"
          lines << ''
          lines << '### Skills by scenario count (engineering priority)'
          rankings[:by_eval_scenario_coverage].first(15).each do |e|
            next if e[:eval_scenario_count].to_i.zero?

            lines << "- **#{e[:skill_key]}**: #{e[:eval_scenario_count]} scenario(s)"
          end
          lines << ''

          lines << '## Workflows (registered)'
          static[:registered_workflow_keys].each { |k| lines << "- `#{k}`" }
          lines << ''
          lines << '_Workflow usefulness in production requires non-zero `workflow_key_frequency` in audits above._'
          lines << ''

          lines << '## LLM dependence (proxy)'
          lines << "- Share of skill invocations that are deterministic: **#{(metrics[:skill_invocation_deterministic_rate].to_f * 100).round(1)}%** (when invocations exist)."
          lines << '- Interpretation: higher deterministic share means more skill output is template/tool-backed rather than free-form generation.'
          lines << ''

          if eval_pass.present?
            lines << '## Optional eval pass overlay'
            lines << '- Per-scenario pass flags were supplied; see `eval_pass_by_scenario` in structured output.'
            lines << ''
          end

          lines << '## Uncertainty'
          lines << '- Audit metrics depend on traffic and dashboard vs API paths writing `invoked_skills`.'
          lines << '- `affected_final_response` is a platform signal, not a human judgment of clarity.'
          lines.join("\n")
        end
      end
    end
  end
end
