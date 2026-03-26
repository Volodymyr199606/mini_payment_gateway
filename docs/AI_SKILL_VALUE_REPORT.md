# AI skill system — value & evidence

This document explains **how we measure the bounded skill layer’s impact** without pretending to know user satisfaction or revenue. It is meant for engineering planning, demos, interviews, and portfolio storytelling — with **honest, observable signals** only.

## Product intent (merchant-facing)

Engineering optimizes the skill layer for **real merchant scenarios**: operational troubleshooting (failed payments, webhooks), reporting clarity (ledger net, charges/refunds/fees), reconciliation hints (bounded discrepancies + next steps), and support-style explanations (lifecycle, auth vs capture, refunds). Eval fixtures (`skill_scenarios.yml`, `skill_regression_scenarios.yml`) include paths such as ledger summary and **reconciliation-style** questions so regressions catch drift in those product journeys—not just generic invocation.

## What “value” means here

| Layer | What we can claim |
|--------|-------------------|
| **Eval / regression YAML** | Which skills are **contract-tested** (expected invocation paths, boundedness gates). |
| **Production / staging audits** | How often skills run, whether they mark `affected_final_response`, deterministic flags, and workflow keys. |
| **Registry / workflows** | What is **registered by design** (deterministic vs non-deterministic definitions, workflow list). |

We do **not** claim:

- Semantic “better answers” without human eval or user metrics tied to skills.
- Causal “this skill caused conversion” — not wired here.

## Code entry points

| Component | Path | Role |
|-----------|------|------|
| `MetricCalculator` | `app/services/ai/skills/value_analysis/metric_calculator.rb` | Aggregates `ai_request_audits`: skill frequencies, affected rates, workflows, agent mix. |
| `ScenarioScorecard` | `app/services/ai/skills/value_analysis/scenario_scorecard.rb` | Parses `spec/fixtures/ai/skill_scenarios.yml` + `skill_regression_scenarios.yml` for **eval coverage by skill**. |
| `ReportBuilder` | `app/services/ai/skills/value_analysis/report_builder.rb` | Produces structured hash + markdown (rankings + narrative sections). |

## How to generate a snapshot

```bash
bundle exec rake ai:skills:value_report
```

Writes a timestamped markdown file under `tmp/ai_skills/` and prints the same to stdout.

Optional: in `rails console`, scope audits before building:

```ruby
scope = AiRequestAudit.where('created_at > ?', 30.days.ago)
r = Ai::Skills::ValueAnalysis::ReportBuilder.build(audit_scope: scope)
puts r[:markdown]
```

## Key metrics (interpretation)

- **`affected_rate` (per skill)** — Share of invocations where `affected_final_response` is true. Proxy for “skill changed the final reply,” not “users liked it.”
- **`skill_helpfulness_proxy.request_affected_rate`** — Share of **requests** that had at least one skill and at least one `affected_final_response` on an invocation. Coarse “did skills touch the outcome” signal.
- **`skill_invocation_deterministic_rate`** / **`llm_dependency_proxy`** — Share of invocations marked deterministic. **LLM dependence proxy**: higher deterministic share ⇒ more template/tool-backed skill output (model more often clarifies bounded output than invents facts).
- **`deterministic_explanation_with_skill_rate`** — Overlap of deterministic explanations with any skill invocation (correlation, not causation).
- **`deterministic_path_strengthened_rate`** — Requests with `deterministic_explanation_used`, any skill, and at least one **deterministic** skill invocation — proxy for “grounded explanation + bounded deterministic skill.”
- **`fallback_with_skill_rate_given_skill`** — Share of skill-requests that still hit `fallback_used` — worth investigating (planner/tuning), not automatic “bad skill.”
- **`workflow_key_frequency`** / **`workflow_selection_rate`** / **`workflow_breakdown`** — Raw counts, share of skill-requests with a workflow, and per-registered-workflow audit counts vs total workflow events.
- **`eval_scenario_count` (per skill)** — How many YAML scenarios **expect** that skill — engineering priority / regression protection.

## Report output (structured + markdown)

`ReportBuilder` adds:

- **Rankings** — `top_skills_by_eval`, `top_skills_by_production` (when audits exist; score = `affected_rate * ln(invocations+1)`).
- **`agent_summaries`** — Per `AgentRegistry` agent: allowlist, eval weight, production skill mix, `AgentProfiles` caps, **value tier** (high / medium / low / unknown), short narrative.
- **`recommendations`** — `keep_expand`, `watch_or_validate`, `prune_or_simplify` (candidate lists; not automatic product decisions).

## Highest-value story (evidence-based)

1. **Skills with both high eval coverage and strong production signals** (when audits exist) are the best candidates for “v1 platform” stories.
2. **Deterministic skills** (`payment_state_explainer`, `ledger_period_summary`, `webhook_trace_explainer`, etc.) are the clearest **LLM reduction** narrative: domain templates over free-form synthesis.
3. **Workflows** must show non-zero `workflow_key_frequency` in real traffic to justify “multi-step value”; otherwise they remain **design-time** capabilities.

## What remains uncertain

- **Sparse audits** in dev — rely on eval coverage and CI gates.
- **`affected_final_response`** can be true while the user still dislikes the answer — no substitute for product analytics or labeling.
- **Portfolio / interview** — use this report as “observability + eval discipline,” not “AI doubled revenue.”

## Related docs

- `docs/AI_SKILLS_FRAMEWORK.md` — architecture and bounded rules.
- `docs/AI_CI_QUALITY_GATES.md` — skill quality gates in CI.
