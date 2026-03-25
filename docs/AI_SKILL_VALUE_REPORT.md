# AI skill system — value & evidence

This document explains **how we measure the bounded skill layer’s impact** without pretending to know user satisfaction or revenue. It is meant for engineering planning, demos, interviews, and portfolio storytelling — with **honest, observable signals** only.

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
- **`skill_invocation_deterministic_rate`** — Share of invocations marked deterministic. **LLM dependence proxy**: higher deterministic share ⇒ more template/tool-backed skill output.
- **`deterministic_explanation_with_skill_rate`** — Overlap of tool/renderer deterministic explanations with any skill invocation (correlation, not causation).
- **`workflow_key_frequency`** — How often `skill_workflow_metadata` records a workflow (bounded multi-skill paths).
- **`eval_scenario_count` (per skill)** — How many YAML scenarios **expect** that skill — engineering priority / regression protection.

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
