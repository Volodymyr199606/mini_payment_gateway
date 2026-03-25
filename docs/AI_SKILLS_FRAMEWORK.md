# AI skills framework (bounded capabilities)

This document describes the **bounded skill layer** under `Ai::Skills`: reusable capabilities that agents may use, with explicit registration, stable results, and **no** autonomous subagents or recursive planning.

### Official v1 skill platform (frozen)

The current system is the **stable internal v1 platform**: core shapes, registry, per-agent profiles, and bounded workflows are treated as **supportable contracts**, validated in development/test by `Ai::Skills::PlatformV1.validate!`.

- **Boundary & contracts:** [AI_SKILL_PLATFORM_V1.md](AI_SKILL_PLATFORM_V1.md)
- **How to add skills safely:** [AI_EXTENSION_GUIDE.md](AI_EXTENSION_GUIDE.md#adding-a-v1-skill-bounded-platform)

---

## Phase 1 status (complete)

| Outcome | Status |
|---------|--------|
| 1. Bounded skill framework foundation | ✓ BaseSkill, Registry, SkillResult, SkillDefinition, Invoker |
| 2. Refactored domain behaviors into skills | ✓ payment_state_explainer, ledger_period_summary, webhook_trace_explainer, followup_rewriter, discrepancy_detector |
| 3. Controlled skill invocation | ✓ InvocationPlanner, InvocationCoordinator, phases (pre_retrieval, pre_tool, post_tool, pre_composition) |
| 4. Skill usage in audit/debug/replay/analytics | ✓ invoked_skills, UsageSerializer, DiffBuilder.matched_skill_usage |
| 5. Skill evaluation and quality gates | ✓ skill_scenarios.yml, SkillScenarioRunner, invocation/safety/bounded specs |

---

## Phase 2 (composition, more skills, agent tuning)

| Area | Implementation |
|------|----------------|
| Skill composition | `CompositionPlanner`, `CompositionResult`, `ConflictResolver`, `ResponseSlots` |
| Precedence | Deterministic skill output over generic phrasing; `followup_rewriter` style-only slot; additive slots (`supporting_analysis`, `warnings`, `next_steps`) append without replacing deterministic totals |
| Response slots | `primary_explanation`, `supporting_analysis`, `docs_clarification`, `style_transform`, `warnings`, `next_steps` — mapped per skill in `ResponseSlots::SKILL_TO_SLOT` |
| Composition metadata | `contributing_skills`, `suppressed_skills`, `suppressed_reason_codes` (per-skill `reason_code`), `conflict_resolutions`, `filled_response_slots`, `precedence_rules_applied`, `final_skill_composition_mode`, `style_transform_applied`, `deterministic_primary` — merged into `ResponseComposer`’s `composition` hash (safe; no raw payloads) |
| Multi-skill post_tool | `InvocationCoordinator` runs up to `min(agent.max_skills_per_request, MAX_INVOCATIONS_PER_REQUEST)` skills per request; `CompositionPlanner` merges outputs |
| New domain skills | `refund_eligibility_explainer`, `authorization_vs_capture_explainer`, `payment_failure_summary`, `webhook_retry_summary`, `reporting_trend_summary`, `reconciliation_action_summary` |
| Per-agent tuning | `AgentDefinition#max_skills_per_request` (default 2); e.g. `security_compliance` uses 1 |
| **Per-agent profiles** | `AgentProfiles`, `AgentProfile`, `SkillWeights` — preferred skills, max budgets, heavy-skill limits, invocation thresholds |
| **Bounded workflows (optional paths)** | `Ai::Skills::Workflows::Registry`, `Selector`, `Executor`, `WorkflowResult` — explicit 1–3 step sequences; not autonomous planning |

**Out of scope (unchanged):** autonomous subagents, recursive planning, unbounded skill chains. `reporting_trend_summary` does not invent trends without explicit comparative ledger inputs; `reconciliation_action_summary` does not execute actions.

### Bounded multi-skill workflows

A **workflow** is a **named, pre-registered** sequence of at most three skill invocations for one domain use case. It is **not** autonomous planning, **not** recursive skill chaining, and **not** nested agents. Workflows complement the default `InvocationPlanner` loop: when `Workflows::Selector` matches a conservative routing + context pattern, `Workflows::Executor` runs the sequence in order via the same `Invoker` / `InvocationExecutor` path (reason code `bounded_workflow_step`). Nested workflow execution is rejected.

| Workflow key | Steps (order) | When selected (summary) |
|--------------|---------------|-------------------------|
| `payment_explain_with_docs` | `payment_state_explainer` | Tool-resolved `support_faq` or `operational`, payment tool data, **and** docs/policy/API-style message |
| `reconciliation_analysis_workflow` | `discrepancy_detector` → `reconciliation_action_summary` | Tool-resolved `reporting_calculation`, ledger data, **and** reconciliation-style message (mismatch, settlement, etc.) |
| `webhook_failure_analysis_workflow` | `webhook_trace_explainer` → `payment_failure_summary` (second step optional) | Routing `operational`, webhook data, **and** failed/pending delivery or payment-failure context |
| `rewrite_response_workflow` | `followup_rewriter` | Pre-composition concise-rewrite path (same gates as today); metadata attached via `WorkflowResult` |

Disable all workflows with `AI_SKILL_WORKFLOWS_DISABLED=1`.

**Metadata:** `Ai::Skills::Workflows::WorkflowResult#to_audit_hash` includes `workflow_key`, `workflow_selected`, `steps_attempted`, `steps_completed`, `contributing_skills`, `skipped_skills`, `stop_reason`, `success`, `affected_final_response`, `duration_ms`. Persisted on `ai_request_audits.skill_workflow_metadata` (jsonb), merged into `ResponseComposer` composition as `skill_workflow`, and exposed in debug payloads / audit drill-down. Replay compares `workflow_key` in `DiffBuilder` / `RequestReplayer` summaries.

### Per-agent skill profiles

Each agent has a tuned profile (`Ai::Skills::AgentProfiles`) that defines:

- **allowed_skill_keys** — subset of skills the agent may use (must align with `AgentDefinition`)
- **preferred_skill_keys** — ordered list; preferred skills are considered first by `InvocationPlanner`
- **suppressed_skill_keys** — skills allowed but only invoked when additional thresholds are met
- **max_skills_per_request** — hard cap on skill invocations per request (1–2 typical)
- **max_heavy_skills_per_request** — cap on heavy skills (e.g. discrepancy_detector, reporting_trend_summary)
- **performance_sensitivity** — `:low`, `:medium`, `:high` for future cost/latency shaping

**Skill weights** (`SkillWeights`): light (template/cache), medium (single domain call), heavy (multi-call, comparison logic). Used for profile budgets and suppression.

**Invocation thresholds** (explicit, testable):

- `webhook_retry_summary` — only when `delivery_status` is `pending` or `failed` (not `succeeded`)
- `reporting_trend_summary` — when profile suppresses it, only runs if message has trend/compare/previous keywords
- `followup_rewriter` — only when `concise_rewrite_only` + `explanation_rewrite` + prior content present

**Profile budgets** — `InvocationCoordinator` and `InvocationPlanner` use profile `max_skills_per_request`; when budget is reached, no further skills are planned. Heavy-skill budget prevents multiple heavy skills in one request.

**Analytics** — `MetricsBuilder.skill_usage` includes `avg_skills_per_request_by_agent` for profile tuning visibility.

### Skill composition model (Phase 2+)

1. **`ResponseSlots`** — Each registered skill maps to one slot (`SKILL_TO_SLOT`). Slots include `primary_explanation`, `supporting_analysis`, `docs_clarification`, `style_transform`, `warnings`, `next_steps`. Additive slots append text; they do not replace deterministic totals or PI/ledger state.

2. **`ConflictResolver`** — Explicit, testable rules in `ConflictResolver::PRECEDENCE_RULES`:
   - **Deterministic over generic:** If two skills both target `primary_explanation` and one is deterministic and one is not, the deterministic skill wins; the other is suppressed with reason `deterministic_over_generic`.
   - **Canonical primary:** If multiple **deterministic** skills both target `primary_explanation`, one winner is chosen using `ResponseSlots::CANONICAL_PRIMARY_ORDER` (payment state → webhook trace → ledger → …). Losers are suppressed with `canonical_primary_precedence`.
   - **Non-deterministic duplicates:** If multiple non-deterministic skills compete for primary, the first wins; others get `no_duplicate_primary_slot`.
   - **Style only:** `followup_rewriter` fills `style_transform`; the composed reply uses style output as the visible line only when present; it does not replace underlying factual primary content in the resolver’s merge order (primary + supporting + style overlay).
   - **Docs clarification:** `docs_clarification` is additive; if text would duplicate the primary line exactly, it is skipped (`docs_clarification_supports_not_replaces_primary`).

3. **`CompositionPlanner`** — Takes tool `reply_text` plus successful `invocation_results` (with optional `explanation` for merging). Produces **`CompositionResult`** with final `reply_text` and metadata for `ResponseComposer`.

4. **Bounded patterns (not autonomous):** Examples the design supports: ledger primary + discrepancy supporting; payment primary + refund eligibility supporting; tool renderer output + single deterministic explainer; pre-composition rewrite as style-only path.

---

## What a skill is

A **skill** is a named, auditable unit of work implemented by a class inheriting `Ai::Skills::BaseSkill`, registered in `Ai::Skills::Registry`, and optionally allowed per agent via `AgentDefinition#allowed_skill_keys`.

Skills are **not** the same as:

| Concept | Role |
|---------|------|
| **Deterministic tools** (`Ai::Tools::*`) | Read-only merchant-scoped queries with fixed JSON shapes; invoked by tool executor. |
| **Agents** (`Ai::Agents::*`) | Specialist prompts + routing; choose retrieval/orchestration path. |
| **Skills** | Declarative capability labels + bounded execution hook for future orchestration (docs explain, ledger summarize, etc.). |

Skills complement tools: a skill may *orchestrate* tools, reuse domain services, or call existing logic. **v1 registry** includes only implemented, planner-wired skills (no stub-only entries).

---

## v1 skill platform (pruned)

The following were **removed from `Registry` and agent allow-lists** (they were never invoked by `InvocationPlanner`, duplicated tool/renderer output, or returned placeholder text only): `docs_lookup`, `failure_summary`, `time_range_resolution`, `report_explainer`, `transaction_trace`. RAG and deterministic tool explanations remain the source of truth for docs and numeric reporting; reintroduce a skill only when it has a distinct, tested execution path.

---

## Implemented skills

| Skill | Purpose | Slot | Domain logic reused | Agents |
|-------|---------|------|---------------------|--------|
| `payment_state_explainer` | Explain payment intent or transaction status in domain-aware language | primary_explanation | `Ai::Explanations::Renderer`, `TemplateRegistry` (PAYMENT_INTENT, TRANSACTION) | support_faq, operational, security_compliance, reconciliation_analyst |
| `ledger_period_summary` | Summarize ledger totals for a time range | primary_explanation | `Reporting::LedgerSummary`, `Ai::Explanations::Renderer`, `TimeRangeParser` | reporting_calculation, reconciliation_analyst |
| `webhook_trace_explainer` | Explain webhook event delivery status and lifecycle | primary_explanation | `Ai::Explanations::Renderer`, `TemplateRegistry` (WEBHOOK) | operational |
| `followup_rewriter` | Rewrite prior response for simpler/shorter/bullet points without full retrieval | style_transform | `Followups::Resolver` response_style patterns | support_faq, developer_onboarding |
| `discrepancy_detector` | Rule-based reconciliation checks (refunds vs charges, PI vs transactions) | supporting_analysis | `Reporting::LedgerSummary`, domain models | reconciliation_analyst |
| `refund_eligibility_explainer` | Explain remaining refundable amount from captured PI | supporting_analysis | `PaymentIntent#refundable_cents`, `total_refunded_cents` | support_faq, operational, reconciliation_analyst |
| `authorization_vs_capture_explainer` | Clarify authorization vs capture lifecycle from PI status | supporting_analysis | Domain states + templates | support_faq, operational, security_compliance, reconciliation_analyst |
| `payment_failure_summary` | Summarize what failed and where in the payment lifecycle | primary_explanation | PI/transaction status, domain states | support_faq, operational |
| `webhook_retry_summary` | Summarize webhook delivery retry status and operational meaning | supporting_analysis | `WebhookDeliveryService` (attempts, delivery_status), webhook event data | operational |
| `reporting_trend_summary` | Summarize short-term trends from comparative ledger data | supporting_analysis | `Reporting::LedgerSummary` (current vs previous period) | reporting_calculation, reconciliation_analyst |
| `reconciliation_action_summary` | Suggest bounded next steps for reconciliation follow-up | next_steps | Ledger consistency checks, discrepancy patterns | reconciliation_analyst |

These skills are **bounded**: they perform a single domain job, have clear inputs/outputs, do not spawn subagents, and do not recursively invoke other skills. Results expose stable metadata (`skill_key`, `deterministic`, `success`) for audit, debug, replay, and analytics.

---

## Core types

| Class | Purpose |
|-------|---------|
| `Ai::Skills::BaseSkill` | Abstract `execute(context:)` → `SkillResult`. |
| `Ai::Skills::SkillDefinition` | Metadata: key, description, deterministic flag, dependencies (`:retrieval`, `:tools`, `:memory`, `:context`), input/output contract strings. |
| `Ai::Skills::SkillResult` | Stable payload: `skill_key`, `success`, `data`, `explanation`, `metadata`, `safe_for_composition`, `deterministic`, optional `error_code` / `error_message`. |
| `Ai::Skills::Registry` | Explicit `SKILLS` hash (symbol → class). `validate!` checks subclasses of `BaseSkill` and definition consistency. |
| `Ai::Skills::Invoker` | **Single** invocation: `Invoker.call(agent_key:, skill_key:, context:)` — checks agent allows skill, then `execute`. No chains. |
| `Ai::Skills::InvocationContext` | Phase-specific request state for planning: `for_pre_composition`, `for_post_tool`. |
| `Ai::Skills::InvocationPlanner` | Rule-based: `plan(context:, already_invoked:)` → `{ skill_key:, reason_code: }` or nil. |
| `Ai::Skills::InvocationExecutor` | Runs planned skill via `Invoker`; returns `InvocationResult`. |
| `Ai::Skills::InvocationCoordinator` | Pipeline integration: `post_tool`, `try_pre_composition_rewrite`. |
| `Ai::Skills::CompositionPlanner` | Merges tool reply + skill `invocation_results` → `CompositionResult` + final `reply_text`. |
| `Ai::Skills::CompositionResult` | Stable composition metadata: slots filled, contributing/suppressed skills, precedence applied. |
| `Ai::Skills::ConflictResolver` | Explicit precedence when multiple skills target the same slot (see `PRECEDENCE_RULES`). |
| `Ai::Skills::ResponseSlots` | Maps skill keys → slot names; additive vs style-only slots. |
| `Ai::Skills::AgentProfile` | Per-agent tuning: preferred skills, budgets, suppression. |
| `Ai::Skills::AgentProfiles` | Registry of profiles; `AgentProfiles.for(agent_key)`. |
| `Ai::Skills::SkillWeights` | Light/medium/heavy classification for performance budgets. |

---

## Registering a skill

1. Subclass `Ai::Skills::BaseSkill`.
2. Define `DEFINITION = Ai::Skills::SkillDefinition.new(...)`.
3. Implement `execute(context:)` returning `SkillResult.success` / `.failure`.
4. Add the class to `Ai::Skills::Registry::SKILLS` with a unique symbol key.
5. Add the key to relevant `AgentDefinition` `allowed_skill_keys` in `Ai::AgentRegistry::DEFINITIONS`.

There is **no** autoload discovery: all registrations are explicit.

---

## Agent → skill mapping

Each `Ai::Agents::AgentDefinition` includes `allowed_skill_keys: []` and `max_skills_per_request` (default 2, capped by `InvocationPlanner::MAX_INVOCATIONS_PER_REQUEST`). Only listed skills may be invoked via `Invoker` for that agent. Example mappings:

| Agent | Example allowed skills |
|-------|-------------------------|
| `support_faq` | `payment_state_explainer`, `followup_rewriter`, `refund_eligibility_explainer`, `authorization_vs_capture_explainer`, `payment_failure_summary` |
| `developer_onboarding` | `followup_rewriter`, `authorization_vs_capture_explainer` |
| `security_compliance` | `payment_state_explainer`, `authorization_vs_capture_explainer` |
| `operational` | `webhook_trace_explainer`, `payment_state_explainer`, `payment_failure_summary`, `webhook_retry_summary` |
| `reporting_calculation` | `ledger_period_summary`, `reporting_trend_summary` |
| `reconciliation_analyst` | `ledger_period_summary`, `discrepancy_detector`, `payment_state_explainer`, `refund_eligibility_explainer`, `authorization_vs_capture_explainer`, `reporting_trend_summary`, `reconciliation_action_summary` |

`Ai::AgentRegistry.validate!` ensures every referenced skill key exists in `Ai::Skills::Registry`.

---

## Skill invocation layer

Agents use skills only when explicitly planned by `InvocationPlanner`. Decision rules are phase-based and capability-checked.

### Invocation phases

| Phase | When | Example skills |
|-------|------|----------------|
| `pre_retrieval` | Before retrieval (no skills wired yet) | — |
| `pre_tool` | Before tool execution (no skills wired yet) | — |
| `post_tool` | After deterministic tool(s) return | `payment_state_explainer`, `webhook_trace_explainer`, `ledger_period_summary`, `discrepancy_detector`, `refund_eligibility_explainer`, `authorization_vs_capture_explainer`, `payment_failure_summary`, `webhook_retry_summary`, `reporting_trend_summary`, `reconciliation_action_summary` |
| `pre_composition` | Before final response; concise_rewrite path | `followup_rewriter` |

### Decision rules (rule-based, explicit)

- **followup_rewriter (pre_composition):** When `execution_mode == :concise_rewrite_only`, `followup_type == :explanation_rewrite`, and `prior_assistant_content` present. Agent must allow `followup_rewriter`.
- **payment_state_explainer (post_tool):** When tool returned payment intent or transaction data. Agent must allow it (e.g. `operational`, `support_faq`).
- **webhook_trace_explainer (post_tool):** When tool returned webhook event data. Agent must allow it (`operational`).
- **ledger_period_summary (post_tool):** When tool returned ledger data. Agent must allow it (`reporting_calculation`, `reconciliation_analyst`).
- **discrepancy_detector (post_tool):** When ledger data present and agent allows it (`reconciliation_analyst`).
- **refund_eligibility_explainer (post_tool):** After `payment_state_explainer`, when captured PI + refund keywords. Agent must allow it.
- **authorization_vs_capture_explainer (post_tool):** After `payment_state_explainer`, when auth/capture keywords. Agent must allow it.
- **payment_failure_summary (post_tool):** When payment/transaction data indicates failure (failed PI, failed txn). Agent must allow it.
- **webhook_retry_summary (post_tool):** When webhook data present and delivery is `pending` or `failed`. Agent must allow it (`operational`).
- **reporting_trend_summary (post_tool):** When ledger data present. Agent must allow it (`reporting_calculation`, `reconciliation_analyst`).
- **reconciliation_action_summary (post_tool):** When ledger data present. Agent must allow it (`reconciliation_analyst`).

### Invocation limits

- Max **2** skill invocations per request (configurable via `InvocationPlanner::MAX_INVOCATIONS_PER_REQUEST`).
- No recursive planning, no skill-calls-skill, no agent spawning subagents.

### Audit and debug

Skill usage is normalized via `Ai::Skills::UsageSerializer` and exposed consistently across audit, debug, replay, and analytics.

**Metadata shape (safe, stable):** `skill_key`, `agent_key`, `phase`, `invoked`, `success`, `deterministic`, `reason_code`, `affected_final_response`, `duration_ms` (when available). Raw inputs, prompts, and sensitive data are **not** persisted or displayed.

**Where it appears:**
- **Audit trail:** `invoked_skills` (jsonb) on `AiRequestAudit` stores normalized skill usage per request. `RecordBuilder` and `Writer` persist it via the existing flow.
- **Debug payload / UI:** When debug is enabled, the response includes `invoked_skills` and `skill_affected_response`. The dashboard debug panel shows a "Skills" section (skills invoked, phases, success/failure, whether the skill changed the final response).
- **Replay:** `RequestReplayer` compares `skill_keys` and `invoked_skills` between original and replayed runs. `DiffBuilder.matched_skill_usage` indicates whether skill usage matches.
- **Analytics:** `MetricsBuilder.skill_usage` aggregates `skill_keys_frequency`, `by_agent`, `avg_skills_per_request_by_agent`, `success_rate`, `deterministic_rate`, `affected_response_count`.
- **Observability:** `EventLogger.log_skill_invocation` emits per-invocation events; `log_ai_request` accepts optional `invoked_skills` for the final request log.

**What is intentionally not persisted/displayed:** raw skill inputs, internal prompts, merchant/account data beyond what existing audit allows, large output blobs (only concise summaries).

---

## Policy and future integration

- **Today:** `Invoker` enforces **agent allowlist** only; execution is a single skill call.
- **Later:** Insert `Policy::Engine` (or tool-style `allow_record?`) before `execute` when skills touch merchant data.
- **Metadata:** `SkillResult#to_h` is safe for audit/debug/replay (no raw secrets); include `skill_key`, `deterministic`, `success`.

---

## Intentionally out of scope

- Recursive skill chains or “skill A calls skill B.”
- Autonomous subagents or unbounded planning loops.
- Dynamic discovery of skills from the filesystem.

Use **explicit** orchestration in `RequestPlanner` / composers if multi-step flows are needed.

---

## Tests

- `spec/services/ai/skills/usage_serializer_spec.rb` — `UsageSerializer` normalize/summary, safe shape, no unsafe leakage.
- `spec/services/ai/skills/*` — `SkillResult`, `SkillDefinition`, `Registry`, `Invoker`, agent allowlists.
- `spec/services/ai/skills/payment_state_explainer_spec.rb` — payment intent and transaction explanation.
- `spec/services/ai/skills/ledger_period_summary_spec.rb` — ledger summary and presets.
- `spec/services/ai/skills/webhook_trace_explainer_spec.rb` — webhook delivery status.
- `spec/services/ai/skills/followup_rewriter_spec.rb` — rewrite modes (bullet, shorter, only_important).
- `spec/services/ai/skills/discrepancy_detector_spec.rb` — aligned vs inconsistent records.
- `spec/services/ai/skills/payment_failure_summary_spec.rb` — failed PI/txn summaries.
- `spec/services/ai/skills/webhook_retry_summary_spec.rb` — webhook retry/delivery status.
- `spec/services/ai/skills/reporting_trend_summary_spec.rb` — comparative ledger trends.
- `spec/services/ai/skills/reconciliation_action_summary_spec.rb` — next-step guidance.
- `spec/services/ai/skills/agent_profiles_spec.rb` — profile budgets and preferences.
- `spec/services/ai/skills/skill_weights_spec.rb` — light/medium/heavy classification.

---

## Skill evaluation and quality gates

Skill quality is evaluated via:

- **Skill scenarios** (`spec/fixtures/ai/skill_scenarios.yml`): YAML scenarios with `expected_skill_keys` and `expected_skill_affected_response`. Run via `Ai::Evals::Skills::SkillScenarioRunner` and `spec/ai/evals/skills/skill_scenarios_spec.rb`.
- **Skill regression scenarios** (`spec/fixtures/ai/skill_regression_scenarios.yml`): Same runner pipeline with extra **boundedness** fields on each scenario: `must_include_skills`, `must_not_include_skills`, `max_invoked_skills`, `max_heavy_skills`. Assertions run inside `Ai::Evals::ScenarioRunner` (`passed_regression`). Use `Ai::Evals::Skills::SkillRegressionRunner` or `spec/ai/skills/regression/skill_regression_scenarios_spec.rb`.
- **Invocation correctness** (`spec/ai/evals/skills/invocation_correctness_spec.rb`): InvocationPlanner rules, agent allowlist, phase selection.
- **Safety** (`spec/ai/evals/skills/skill_safety_spec.rb`): Merchant scoping, policy boundaries, output safety (UsageSerializer, QualityMetadata).
- **Bounded invocation** (`spec/ai/evals/skills/skill_bounded_invocation_spec.rb`): MAX_INVOCATIONS_PER_REQUEST, audit metadata presence.
- **Metadata contracts** (`spec/ai/skills/contracts/`): Stable keys on `InvocationResult#to_audit_hash`, `UsageSerializer`, `CompositionResult#to_audit_hash`; `Ai::Evals::Skills::SkillMetadataContract`.
- **Agent drift** (`spec/fixtures/ai/agent_skill_expectations.yml`, `spec/ai/skills/drift/`): `must_allow` / `must_not_allow` per agent vs `AgentProfiles` allowlists.
- **Noise rules** (`Ai::Evals::Skills::SkillNoiseRules`, `spec/ai/skills/noise/`): Explicit predicates (e.g. rewriter without style path, heavy skills on trivial support).
- **Performance smoke** (`spec/ai/skills/performance/`): Structural checks (planner caps, `MetricSamples`, relative median ratio helpers). **Wall-clock ratio** scenarios are tagged `:perf_local` and run with `RUN_PERF_LOCAL=1` or `rake ai:skills:perf:local` (reports under `tmp/ai_skills/`). CI runs non-local perf smoke only.

### CI and local commands

| Command | What it runs |
|---------|----------------|
| `bin/ci_ai_skills` / `rake ai:skills:ci` | All skill gate specs: `spec/ai/skills/`, `spec/ai/evals/skills/` |
| `rake ai:skills:regression` | Regression YAML scenarios only |
| `rake ai:skills:contracts` | Contract specs only |
| `rake ai:skills:perf` | Perf smoke (excludes `:perf_local`) |
| `rake ai:skills:drift` | Drift + noise specs |
| `rake ai:skills:perf:local` | Median ratio regression (optional; not default in CI) |
| `bin/ci_ai` / `rake ai:ci` | Full AI gates **including** skill quality (same paths as CI) |

**Drift / regression:** Failing `must_not_include_skills` or `max_heavy_skills` usually means invocation planner, profile, or composition changed selectivity. Failing `agent_skill_expectations.yml` means an agent allowlist drifted against documented role boundaries. Update YAML and docs when behavior changes **by design**.

**No LLM wording:** Scenarios do not assert on free-form model text; they assert on skill keys, invocation counts, composition metadata, and tool/path expectations only.

**Correctness per skill:**
- `payment_state_explainer`: Invoked when post_tool + payment/transaction data; agent allows it. Deterministic template output.
- `webhook_trace_explainer`: Invoked when post_tool + webhook data; operational agent. Deterministic.
- `webhook_retry_summary`: Invoked when post_tool + webhook data; operational agent. Deterministic.
- `ledger_period_summary`: Invoked when post_tool + ledger data; reporting_calculation agent. Deterministic.
- `reporting_trend_summary`: Invoked when post_tool + ledger data; reporting_calculation/reconciliation_analyst. Deterministic.
- `reconciliation_action_summary`: Invoked when post_tool + ledger data; reconciliation_analyst. Deterministic.
- `payment_failure_summary`: Invoked when post_tool + failed PI/txn data; support_faq/operational. Deterministic.
- `followup_rewriter`: Invoked when pre_composition + concise_rewrite + prior content; support_faq allows it. Not deterministic.
- `discrepancy_detector`: Invoked when post_tool + ledger data; reconciliation_analyst allows it.

**Quality metadata** (`Ai::Evals::Skills::QualityMetadata`): `skill_expected`, `skill_invoked`, `skill_helpful`, `skill_blocked_by_policy`, `skill_unnecessary`, `skill_affected_response`, `skill_quality_notes`. Used for tests and replay comparison.

### Value & impact evidence (internal)

Observable **business/value** storytelling uses audit aggregates + eval coverage — not subjective “smarter” claims:

| Component | Purpose |
|-----------|---------|
| `Ai::Skills::ValueAnalysis::MetricCalculator` | From `ai_request_audits`: skill frequencies, `affected_final_response` / helpfulness-style proxies, deterministic share, workflow keys & per-workflow breakdown, strengthened-deterministic-path proxy, per-`agent_key` mix. |
| `Ai::Skills::ValueAnalysis::ScenarioScorecard` | From `spec/fixtures/ai/skill_scenarios.yml` + `skill_regression_scenarios.yml`: how many scenarios expect each skill. |
| `Ai::Skills::ValueAnalysis::ReportBuilder` | Markdown + structured hash: rankings, per-agent value tiers, keep/watch/prune candidates. |

Run `bundle exec rake ai:skills:value_report` (writes under `tmp/ai_skills/`). See **[AI_SKILL_VALUE_REPORT.md](AI_SKILL_VALUE_REPORT.md)** for interpretation and limits.

---

## References

- Tools: [AI_AGENTS.md](AI_AGENTS.md), `app/services/ai/tools/registry.rb`
- Agents: `app/services/ai/agent_registry.rb`
- Policy: `app/services/ai/policy/`
