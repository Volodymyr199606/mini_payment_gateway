# AI skill platform v1 (official, frozen boundary)

This document defines the **stable internal platform** for bounded skills: what is supported, what is locked, how to extend it safely, and what is intentionally **out of scope**.

Implementation anchor: `Ai::Skills::PlatformV1` (`app/services/ai/skills/platform_v1.rb`).

| Label | Value |
|--------|--------|
| Platform version | `Ai::Skills::PlatformV1::VERSION` (bump on intentional platform-level changes) |
| Contract schema | `Ai::Skills::PlatformV1::CONTRACT_SCHEMA_VERSION` (bump with migration plan for audit/composition hashes) |

---

## What v1 is

- A **bounded** capability layer: registered skills, explicit invocation phases, composition with fixed precedence rules, optional **pre-registered workflows** (1–3 steps), full audit/replay metadata.
- **Not** autonomous agents, recursive planning, dynamic workflow synthesis, or arbitrary skill chains.

---

## Stable contracts (do not change casually)

| Surface | Class / module | Stable expectations |
|---------|----------------|----------------------|
| Skill implementation | `Ai::Skills::BaseSkill` | Subclass defines `DEFINITION` (`SkillDefinition`), implements `#execute(context:)` → `SkillResult`. |
| Skill output | `Ai::Skills::SkillResult` | `CONTRACT_SCHEMA_VERSION`; `#to_h` keys: `skill_key`, `success`, `explanation`, `metadata`, `safe_for_composition`, `deterministic`, `error_code`, `error_message`, optional `data`. |
| Registry entry | `Ai::Skills::SkillDefinition` | `key`, `class_name`, `description`, `deterministic`, `dependencies` (subset of `DEPENDENCY_KEYS`), optional contract strings. |
| Invocation attempt | `Ai::Skills::InvocationResult` | `#to_audit_hash` for planner/audit; aligns with `Ai::Evals::Skills::SkillMetadataContract`. |
| Composition | `Ai::Skills::CompositionResult` | `CONTRACT_SCHEMA_VERSION`; `#to_audit_hash` keys documented on the class. |
| Workflow run | `Ai::Skills::Workflows::WorkflowResult` | `CONTRACT_SCHEMA_VERSION`; `#to_audit_hash`; `STOP_REASONS` closed set. |
| Workflow definition | `Ai::Skills::Workflows::WorkflowDefinition` | `MAX_SKILL_STEPS = 3`; fixed fields only. |
| Audit normalization | `Ai::Skills::UsageSerializer::SAFE_KEYS` | Whitelisted keys for persisted skill usage rows. |
| Response slots | `Ai::Skills::ResponseSlots::SLOT_NAMES`, `SKILL_TO_SLOT`, `ConflictResolver::PRECEDENCE_RULES` | Every **registered** skill must map to a slot; precedence rules are part of the platform. |

Bump `CONTRACT_SCHEMA_VERSION` on `SkillResult`, `CompositionResult`, and `WorkflowResult` **together** with `PlatformV1::CONTRACT_SCHEMA_VERSION` and a short migration note (replay/analytics consumers).

---

## Official v1 skills

Source of truth: `Ai::Skills::Registry::SKILLS` (same as `Ai::Skills::PlatformV1.official_skill_keys`).

Adding or removing a skill is a **platform change**: registry, `ResponseSlots::SKILL_TO_SLOT`, `SkillWeights::WEIGHTS`, agent allowlists, eval fixtures, and docs.

---

## Official v1 agent profiles

Source of truth: `Ai::Skills::AgentProfiles::PROFILES`.

Rules:

- For each agent in `Ai::AgentRegistry::DEFINITIONS`, **`allowed_skill_keys` must match exactly** between `AgentDefinition` and `AgentProfile`.
- **`max_skills_per_request` on the profile must not exceed** `AgentDefinition#max_skills_per_request`.
- Preferred / suppressed lists and heavy-skill budgets are **reviewable tuning**, not ad-hoc edits in hot paths.

Boot validation: `Ai::Skills::PlatformV1.validate!` (development/test).

---

## Official v1 workflows

Source of truth: `Ai::Skills::Workflows::Registry` (see `Ai::Skills::PlatformV1.official_workflow_keys`).

| Key | Intent |
|-----|--------|
| `payment_explain_with_docs` | Single-step payment explanation for docs/policy-style questions. |
| `reconciliation_analysis_workflow` | Discrepancy scan → bounded reconciliation next steps. |
| `webhook_failure_analysis_workflow` | Webhook trace → optional payment failure summary. |
| `rewrite_response_workflow` | Style rewrite (`followup_rewriter`) on pre-composition path. |

Disable at runtime: `AI_SKILL_WORKFLOWS_DISABLED=1`. Adding a workflow requires registry entry, selector rules, tests, and this doc.

---

## Supported extension model (summary)

Detailed steps: **[AI_EXTENSION_GUIDE.md](AI_EXTENSION_GUIDE.md)** (skills section).

Discipline:

1. Implement `BaseSkill` + `SkillDefinition`.
2. Register in `Ai::Skills::Registry::SKILLS`.
3. Map `ResponseSlots::SKILL_TO_SLOT` and `SkillWeights::WEIGHTS`.
4. Add `allowed_skill_keys` to `AgentDefinition` and mirror in `AgentProfiles::PROFILES`.
5. Wire planner/coordinator if new phase or threshold rules apply.
6. Persist safe usage via `UsageSerializer` / `InvocationResult`.
7. Add YAML evals and CI gates (`spec/ai/evals/skills/`, `spec/ai/skills/`).

---

## Intentionally out of scope for v1

Mirrors `Ai::Skills::PlatformV1::OUT_OF_SCOPE`:

- Autonomous subagents and nested workflow execution.
- Recursive or open-ended planning over skills.
- Dynamic workflow generation at runtime.
- Arbitrary skill chaining beyond registered workflows + planner budget.
- Runtime discovery of skills (no autoload registry).

**Non-v1 placeholders:** `ResponseSlots::RESERVED_NON_V1_SKILL_KEYS` and matching `SkillWeights` entries — not in `Registry`; do not treat as supported skills until promoted through the full extension checklist.

---

## CI / validation

- `config/initializers/ai_registries.rb` runs `Ai::Skills::PlatformV1.validate!` in development/test.
- Contract tests: `spec/services/ai/skills/platform_v1_spec.rb`, registry/workflow specs, metadata contract specs.

---

## Merchant-facing value (product intent)

The v1 platform is tuned for **operator and merchant** questions—not internal demos. Typical high-value paths:

| Merchant need | Primary agents / tools | Skills & workflows |
|---------------|------------------------|---------------------|
| Why did a payment fail? What’s wrong with this refund/capture? | `operational`, `support_faq` + PI/txn tools | `payment_state_explainer`, `payment_failure_summary` |
| Why is this still authorized / requires capture? | `support_faq`, `operational` | `payment_state_explainer` (deterministic templates in `TemplateRegistry`) |
| Webhook stuck, retrying, or failed delivery? | `operational` + `get_webhook_event` | `webhook_trace_explainer`, `webhook_retry_summary`; workflow `webhook_failure_analysis_workflow` when applicable |
| Net volume, charges, refunds, fees in plain language | `reporting_calculation` + `get_ledger_summary` | `ledger_period_summary`; `reporting_trend_summary` only when a prior period is comparable |
| “Does this look right?” / reconciliation | `reporting_calculation` / `reconciliation_analyst` + ledger | `discrepancy_detector`, `reconciliation_action_summary`; workflow `reconciliation_analysis_workflow` |
| Simpler/shorter answers | `support_faq`, `developer_onboarding` | `followup_rewriter` (pre-composition); workflow `rewrite_response_workflow` when applicable |

Copy and behavior live in **deterministic templates** (`app/services/ai/explanations/template_registry.rb`) and **skill classes** under `app/services/ai/skills/`. Changes there are product-visible; keep them bounded and auditable.

---

## Related docs

- [AI_SKILLS_FRAMEWORK.md](AI_SKILLS_FRAMEWORK.md) — architecture and behavior.
- [AI_EXTENSION_GUIDE.md](AI_EXTENSION_GUIDE.md) — how to add agents, tools, and **v1 skills**.
- [AI_CI_QUALITY_GATES.md](AI_CI_QUALITY_GATES.md) — skill CI gates.
- [AI_SKILL_VALUE_REPORT.md](AI_SKILL_VALUE_REPORT.md) — evidence-based value metrics.
