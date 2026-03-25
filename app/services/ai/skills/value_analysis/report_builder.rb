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
          agent_summaries = derive_agent_summaries(metrics, coverage)
          recommendations = derive_recommendations(metrics, rankings, agent_summaries, static)

          {
            generated_at: Time.zone.now.iso8601,
            audit_scope_description: scope_description,
            metrics: metrics,
            scenario_coverage: coverage,
            scenario_scorecard_summary: scorecard_summary,
            eval_pass_by_scenario: eval_pass.presence,
            static: static,
            rankings: rankings,
            agent_summaries: agent_summaries,
            recommendations: recommendations,
            markdown: render_markdown(
              metrics, coverage, scorecard_summary, static, eval_pass, rankings,
              agent_summaries, recommendations
            )
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
            top_skills_by_eval: by_eval.select { |e| e[:eval_scenario_count].to_i.positive? }.first(8),
            top_skills_by_production: by_prod.first(8),
            notes: [
              'Rankings are evidence helpers, not revenue or user-satisfaction scores.',
              'production_signal_score = affected_rate * ln(invocation_count + 1) when audits exist.',
              'Skills with eval coverage but zero production data are still engineering-validated.'
            ]
          }
        end

        def derive_agent_summaries(metrics, coverage)
          audit_n = metrics[:audit_sample_size].to_i
          mix = metrics[:skill_invocations_by_audit_agent] || {}

          Ai::AgentRegistry::DEFINITIONS.keys.map do |agent_key|
            defn = Ai::AgentRegistry.definition(agent_key)
            allowed = Array(defn&.allowed_skill_keys).map(&:to_s)
            eval_weight = allowed.sum { |sk| coverage[sk]&.dig(:scenario_count).to_i }
            prod = mix[agent_key.to_s] || {}
            prod_inv = prod.values.sum
            profile = Ai::Skills::AgentProfiles.for(agent_key)

            {
              agent_key: agent_key.to_s,
              allowed_skills: allowed,
              eval_scenario_weight: eval_weight,
              production_invocation_total: prod_inv,
              skill_mix: prod,
              value_tier: tier_for_agent(agent_key, eval_weight, prod_inv, audit_n),
              profile: {
                max_skills_per_request: profile.max_skills_per_request,
                max_heavy_skills_per_request: profile.max_heavy_skills_per_request,
                performance_sensitivity: profile.performance_sensitivity
              },
              narrative: agent_narrative(agent_key)
            }
          end
        end

        def tier_for_agent(agent_key, eval_weight, prod_inv, audit_n)
          # security_compliance is intentionally narrow; "low" tier can still be correct product design.
          if eval_weight.zero? && prod_inv.zero?
            return audit_n.positive? ? :low : :unknown
          end

          if %i[support_faq operational reconciliation_analyst].include?(agent_key) && (eval_weight >= 3 || prod_inv >= 5)
            return :high
          end

          if agent_key == :security_compliance
            return (eval_weight.positive? || prod_inv.positive?) ? :medium : :low
          end

          return :high if eval_weight >= 4 && prod_inv.positive?
          return :medium if eval_weight.positive? || prod_inv.positive?

          :low
        end

        def agent_narrative(agent_key)
          {
            support_faq: 'Payment + refund explainers, failure summary, rewrite — primary support surface.',
            operational: 'Webhook trace/retry + payment failure paths — operations-heavy.',
            reporting_calculation: 'Ledger + optional trend — deterministic reporting.',
            reconciliation_analyst: 'Ledger + discrepancy + next steps — analysis-heavy.',
            developer_onboarding: 'Auth/capture explainer + rewrite — narrow by design.',
            security_compliance: 'Intentionally small allowlist; conservative skill use.'
          }[agent_key.to_sym] || 'See AgentRegistry allowlist.'
        end

        def derive_recommendations(metrics, rankings, agent_summaries, _static)
          watch = []
          keep = []
          has_audits = metrics[:audit_sample_size].to_i.positive?

          (rankings[:top_skills_by_eval] || []).each do |e|
            next if e[:eval_scenario_count].to_i < 2

            keep << "Eval-heavy: #{e[:skill_key]} (#{e[:eval_scenario_count]} scenarios)"
          end

          if has_audits && metrics[:workflow_audit_count].to_i.positive?
            (metrics[:workflow_breakdown] || {}).each do |wk, row|
              next if row[:audit_count].to_i.positive?

              watch << "Workflow `#{wk}`: no audit hits in scope — validate in production traffic for v1 narrative."
            end
          elsif has_audits && metrics[:requests_with_any_skill].to_i.positive? && metrics[:workflow_audit_count].to_i.zero?
            watch << 'Workflows: requests have skills but no `skill_workflow_metadata` in scope — workflows may be rare or path-limited.'
          end

          agent_summaries.each do |a|
            next unless a[:value_tier] == :unknown

            watch << "Agent #{a[:agent_key]}: insufficient eval + audit evidence in this scope — #{a[:narrative]}"
          end

          {
            keep_expand: keep.uniq.first(10),
            watch_or_validate: watch.uniq.first(15),
            prune_or_simplify: [
              'Skills/workflows with zero eval coverage and zero production invocations (see rankings) are candidates to trim or merge — confirm before removing.',
              'Review `fallback_with_skill_rate_given_skill` vs baseline; elevated fallback with skills may warrant planner tuning (not automatic prune).'
            ]
          }
        end

        def render_markdown(metrics, coverage, scorecard_summary, static, eval_pass, rankings,
                            agent_summaries, recommendations)
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
            lines << "- Skill helpfulness proxy (request): **#{(metrics.dig(:skill_helpfulness_proxy, :request_affected_rate).to_f * 100).round(1)}%** of skill-requests had `affected_final_response` on at least one skill"
            lines << "- Skill invocations (total rows): **#{metrics[:skill_invocation_total]}**; deterministic share: **#{(metrics[:skill_invocation_deterministic_rate].to_f * 100).round(1)}%**"
            lines << "- deterministic_explanation_used ∧ skill: **#{metrics[:deterministic_explanation_with_any_skill]}** (#{(metrics[:deterministic_explanation_with_skill_rate].to_f * 100).round(1)}% of requests with skills)"
            lines << "- Deterministic path strengthened (det_expl ∧ skill ∧ deterministic skill): **#{metrics[:deterministic_path_strengthened_requests]}** (#{(metrics[:deterministic_path_strengthened_rate].to_f * 100).round(1)}% of skill-requests)"
            lines << "- Fallback despite skills (investigate): **#{metrics[:fallback_with_skill_requests]}** (#{(metrics[:fallback_with_skill_rate_given_skill].to_f * 100).round(1)}% of skill-requests)"
            lines << "- Workflow selection rate: **#{(metrics[:workflow_selection_rate].to_f * 100).round(1)}%** of skill-requests recorded a workflow"
            lines << ''
            lines << '### Workflow keys (audit metadata)'
            if metrics[:workflow_key_frequency].present?
              metrics[:workflow_key_frequency].each { |k, v| lines << "- `#{k}`: #{v}" }
            else
              lines << '- (none in scope)'
            end
            lines << ''
            lines << '### Workflows (registered vs audits in scope)'
            (metrics[:workflow_breakdown] || {}).sort_by { |k, _| k }.each do |wk, row|
              lines << "- **#{wk}**: audits=#{row[:audit_count]}, share_of_workflow_events=#{(row[:share_of_workflow_audits].to_f * 100).round(1)}%"
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

          lines << '## Highest-value skills (evidence blend)'
          lines << '- **By eval fixtures** (regression protection): top scenario coverage.'
          (rankings[:top_skills_by_eval] || []).each do |e|
            lines << "- **#{e[:skill_key]}**: #{e[:eval_scenario_count]} scenario(s)"
          end
          lines << '- **By production signal** (when audits exist): `affected_rate * ln(invocations+1)`.'
          (rankings[:top_skills_by_production] || []).each do |e|
            next if e[:production_signal_score].blank?

            lines << "- **#{e[:skill_key]}**: score=#{e[:production_signal_score]} (inv=#{e[:production_invocation_count]}, affected_rate=#{e[:production_affected_rate]})"
          end
          lines << ''

          lines << '## Agents — skill value (tier + mix)'
          agent_summaries.sort_by { |a| a[:agent_key] }.each do |a|
            lines << "- **#{a[:agent_key]}** — tier `#{a[:value_tier]}` | eval_weight=#{a[:eval_scenario_weight]} | prod_inv=#{a[:production_invocation_total]} | max_skills/req=#{a[:profile][:max_skills_per_request]}"
            lines << "  - #{a[:narrative]}"
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

          lines << '## Recommendations (keep / watch / prune candidates)'
          lines << '### Keep / expand'
          if recommendations[:keep_expand].present?
            recommendations[:keep_expand].each { |x| lines << "- #{x}" }
          else
            lines << '- _(none in this run — add eval scenarios or widen audit scope.)_'
          end
          lines << ''
          lines << '### Watch / validate'
          if recommendations[:watch_or_validate].present?
            recommendations[:watch_or_validate].each { |x| lines << "- #{x}" }
          else
            lines << '- _(none)_'
          end
          lines << ''
          lines << '### Prune / simplify (candidates only)'
          recommendations[:prune_or_simplify].each { |x| lines << "- #{x}" }
          lines << ''

          lines << '## Deterministic paths strengthened (proxy)'
          lines << '- **Signal**: `deterministic_explanation_used` ∧ at least one invoked skill ∧ that skill marked `deterministic`.'
          lines << "- **In scope**: **#{metrics[:deterministic_path_strengthened_requests]}** requests (#{(metrics[:deterministic_path_strengthened_rate].to_f * 100).round(1)}% of skill-requests)."
          lines << '- Interpretation: domain explanation path plus bounded deterministic skill output — stronger grounding than generic synthesis alone.'
          lines << ''

          lines << '## LLM dependence (proxy)'
          det_share = metrics.dig(:llm_dependency_proxy, :deterministic_skill_share_of_invocations)
          det_pct = det_share.nil? ? 'n/a' : "#{(det_share.to_f * 100).round(1)}%"
          lines << "- Share of skill invocations that are deterministic: **#{det_pct}** (matches `skill_invocation_deterministic_rate` when invocations exist)."
          lines << '- Interpretation: higher deterministic share means the model is more often **formatting/clarifying** bounded skill output than inventing domain facts.'
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
