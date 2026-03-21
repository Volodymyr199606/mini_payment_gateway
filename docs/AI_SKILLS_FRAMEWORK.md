# AI skills framework (bounded capabilities)

This document describes the **bounded skill layer** under `Ai::Skills`: reusable capabilities that agents may use, with explicit registration, stable results, and **no** autonomous subagents or recursive planning.

---

## What a skill is

A **skill** is a named, auditable unit of work implemented by a class inheriting `Ai::Skills::BaseSkill`, registered in `Ai::Skills::Registry`, and optionally allowed per agent via `AgentDefinition#allowed_skill_keys`.

Skills are **not** the same as:

| Concept | Role |
|---------|------|
| **Deterministic tools** (`Ai::Tools::*`) | Read-only merchant-scoped queries with fixed JSON shapes; invoked by tool executor. |
| **Agents** (`Ai::Agents::*`) | Specialist prompts + routing; choose retrieval/orchestration path. |
| **Skills** | Declarative capability labels + bounded execution hook for future orchestration (docs explain, ledger summarize, etc.). |

Skills complement tools: a skill may *orchestrate* tools, reuse domain services, or call existing logic. Five skills are fully implemented and wrap domain behavior; others remain stubs until orchestration wires them.

---

## Implemented skills (first set)

| Skill | Purpose | Domain logic reused | Agents |
|-------|---------|---------------------|--------|
| `payment_state_explainer` | Explain payment intent or transaction status in domain-aware language | `Ai::Explanations::Renderer`, `TemplateRegistry` (PAYMENT_INTENT, TRANSACTION) | support_faq, operational, security_compliance, reconciliation_analyst |
| `ledger_period_summary` | Summarize ledger totals for a time range | `Reporting::LedgerSummary`, `Ai::Explanations::Renderer`, `TimeRangeParser` | reporting_calculation, reconciliation_analyst |
| `webhook_trace_explainer` | Explain webhook event delivery status and lifecycle | `Ai::Explanations::Renderer`, `TemplateRegistry` (WEBHOOK) | operational |
| `followup_rewriter` | Rewrite prior response for simpler/shorter/bullet points without full retrieval | `Followups::Resolver` response_style patterns | support_faq, developer_onboarding |
| `discrepancy_detector` | Rule-based reconciliation checks (refunds vs charges, PI vs transactions) | `Reporting::LedgerSummary`, domain models | reconciliation_analyst |

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

Each `Ai::Agents::AgentDefinition` includes `allowed_skill_keys: []`. Only listed skills may be invoked via `Invoker` for that agent. Example mappings:

| Agent | Example allowed skills |
|-------|-------------------------|
| `support_faq` | `docs_lookup`, `payment_state_explainer`, `followup_rewriter` |
| `operational` | `webhook_trace_explainer`, `payment_state_explainer`, `failure_summary` |
| `reporting_calculation` | `ledger_period_summary`, `time_range_resolution`, `report_explainer` |
| `reconciliation_analyst` | `ledger_period_summary`, `discrepancy_detector`, `payment_state_explainer`, `transaction_trace` |

`Ai::AgentRegistry.validate!` ensures every referenced skill key exists in `Ai::Skills::Registry`.

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

- `spec/services/ai/skills/*` — `SkillResult`, `SkillDefinition`, `Registry`, `Invoker`, agent allowlists.
- `spec/services/ai/skills/payment_state_explainer_spec.rb` — payment intent and transaction explanation.
- `spec/services/ai/skills/ledger_period_summary_spec.rb` — ledger summary and presets.
- `spec/services/ai/skills/webhook_trace_explainer_spec.rb` — webhook delivery status.
- `spec/services/ai/skills/followup_rewriter_spec.rb` — rewrite modes (bullet, shorter, only_important).
- `spec/services/ai/skills/discrepancy_detector_spec.rb` — aligned vs inconsistent records.

---

## References

- Tools: [AI_AGENTS.md](AI_AGENTS.md), `app/services/ai/tools/registry.rb`
- Agents: `app/services/ai/agent_registry.rb`
- Policy: `app/services/ai/policy/`
