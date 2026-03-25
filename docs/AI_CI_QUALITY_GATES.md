# AI CI Quality Gates

This document describes the CI/CD quality gates for the AI subsystem: what runs, what each gate protects, how to run them locally, and how to update them when contracts or behavior change by design.

---

## Overview

The CI workflow (`.github/workflows/ci.yml`) runs **AI-focused gates** as separate jobs so failures are easy to attribute. All AI tests are **deterministic and self-contained**: no real Groq or external API calls; stubs and fixtures are used. The same gates can be run locally before pushing.

---

## What runs in CI

| Gate | Job name | Spec path(s) | Protects |
|------|----------|--------------|----------|
| **AI contracts** | `ai_contracts` | `spec/ai/contracts/` | RequestPlanner/ExecutionPlan, Policy::Decision, ToolResult, RetrievalResult, RunResult, ResponseComposer, audit/debug payloads, analytics/health, replay result contracts |
| **AI scenarios** | `ai_scenarios` | `spec/ai/end_to_end_scenarios_spec.rb` | End-to-end request flows: routing, tools, policy, composition; uses `spec/fixtures/ai/scenarios.yml` |
| **AI adversarial** | `ai_adversarial` | `spec/ai/adversarial_scenarios_spec.rb` | Merchant isolation, policy enforcement, follow-up inheritance safety, prompt-injection-like behavior, no internal/debug leakage; uses `spec/fixtures/ai/adversarial_scenarios.yml` |
| **AI policy** | `ai_policy` | `spec/ai/authorization_policy_spec.rb` | Authorization and allow_record? behavior for tools and entities |
| **AI internal tooling** | `ai_internal_tooling` | `spec/requests/dev/ai_analytics_spec.rb`, `ai_health_spec.rb`, `ai_audits_spec.rb`, `ai_audits_replay_spec.rb`, `ai_playground_spec.rb` | AI analytics, health, audit drill-down, replay, playground entrypoints (route/controller sanity) |
| **AI docs** | `ai_docs` | `spec/docs/ai_platform_docs_spec.rb` | Required AI platform docs exist (AI_PLATFORM.md, AI_REQUEST_FLOW.md, AI_EXTENSION_GUIDE.md, AI_OPERATIONS.md, AI_SAFETY_AND_POLICY.md, AI_DEBUGGING_AND_REPLAY.md, AI_DEPLOYMENT_AND_RELEASE_SAFETY.md) |
| **AI skills quality** | `ai_skills_quality` | `spec/ai/skills/`, `spec/ai/evals/skills/` | Skill regression YAML (`skill_regression_scenarios.yml`), boundedness, metadata contracts, agent drift expectations, noise rules, perf smoke (no external APIs; no LLM text assertions) |
| **Demo seed (smoke)** | `demo_seed` | `spec/seeds/demo_seed_spec.rb` | Demo seed runs and creates expected core records; optional, lightweight |

After all AI gates pass, the **Spec (rest)** job runs the remaining RSpec specs (excluding the AI gate paths) so the full suite is covered without re-running AI specs.

---

## What each gate protects

### ai_contracts

- **ExecutionPlan** (RequestPlanner) contract: execution modes, audit metadata shape, `contract_version`.
- **Policy::Decision** contract: `allowed`, `decision_type`, `metadata`, `reason_code` / `safe_message` for deny.
- **ToolResult**, **RetrievalResult**, **RunResult**, **ComposedResponse** shapes so consumers and audit/replay stay stable.
- **Audit payload** and **debug payload** contracts so no sensitive data leaks and structure stays predictable.
- **Analytics/health** result contracts for internal tooling.
- **Replay result** contract for replayable request debugging.

### ai_scenarios

- Realistic user flows through the AI stack (orchestration, tools, retrieval, composition).
- Fixture-driven (`spec/fixtures/ai/scenarios.yml`); Groq and ledger are stubbed.
- Fails clearly when path, tool choice, policy, or composition behavior regresses.

### ai_adversarial

- Cross-tenant access attempts (attacker merchant cannot see victim data).
- Policy enforcement and follow-up inheritance safety.
- Prompt-injection-like and context-abuse cases.
- Ensures internal/debug surfaces are not exposed inappropriately.

### ai_policy

- Authorization rules for entity tools (payment intent, transaction, webhook).
- `allow_record?` and merchant scoping.

### ai_internal_tooling

- AI analytics, health, audit list, audit replay, and playground pages return 200 and expected content.
- Route/controller-level smoke; not full UI rendering coverage.

### ai_docs

- Required internal AI platform docs exist.
- Keeps doc set discoverable and referenced by DEMO_SCRIPT and runbooks.

### ai_skills_quality

- **Regression:** `skill_regression_scenarios.yml` — must/must-not skill keys, max invoked/heavy skills; catches planner/profile/composition drift.
- **Contracts:** `SkillMetadataContract` vs `InvocationResult`, `UsageSerializer`, `CompositionResult` shapes.
- **Drift:** `agent_skill_expectations.yml` vs `AgentProfiles` (`must_allow` / `must_not_allow`).
- **Noise:** `SkillNoiseRules` predicates (rewriter without style path, etc.).
- **Evals:** Existing skill scenarios, invocation correctness, safety, bounded invocation under `spec/ai/evals/skills/`.
- **Perf smoke:** Planner caps and relative metrics helpers; deeper wall-clock ratios are `:perf_local` only (`RUN_PERF_LOCAL=1`).

See [AI_SKILLS_FRAMEWORK.md](AI_SKILLS_FRAMEWORK.md) for commands (`bin/ci_ai_skills`, `rake ai:skills:*`). Boot-time **v1 platform** alignment (registry, profiles, workflows, response slots, contract schema versions) is enforced in development/test by `Ai::Skills::PlatformV1.validate!` — see [AI_SKILL_PLATFORM_V1.md](AI_SKILL_PLATFORM_V1.md) and `spec/services/ai/skills/platform_v1_spec.rb`.

### demo_seed (optional)

- Demo seed task creates demo merchant, scoping merchant, and key records.
- Validates seed script and demo data integrity; skips if DB/schema not available.

---

## How to run locally

**One command (all AI gates):**

```bash
bin/ci_ai
```

or:

```bash
RAILS_ENV=test bundle exec rake ai:ci
```

**Skill layer only:**

```bash
bin/ci_ai_skills
```

or `RAILS_ENV=test bundle exec rake ai:skills:ci` (see [AI_SKILLS_FRAMEWORK.md](AI_SKILLS_FRAMEWORK.md)).

Ensure the test database is prepared:

```bash
RAILS_ENV=test bundle exec rails db:create db:schema:load
```

**Individual gates:**

```bash
RAILS_ENV=test bundle exec rake ai:ci:contracts
RAILS_ENV=test bundle exec rake ai:ci:scenarios
RAILS_ENV=test bundle exec rake ai:ci:adversarial
RAILS_ENV=test bundle exec rake ai:ci:policy
RAILS_ENV=test bundle exec rake ai:ci:internal_tooling
bundle exec rake ai:ci:docs
RAILS_ENV=test bundle exec rake ai:ci:skills
```

(`ai:ci:docs` does not require the DB; others do.)

---

## How to interpret failures

- **ai_contracts**: A contract (shape or version) changed. Either a regression in the component that produces the payload, or an intentional contract change that requires updating the contract spec and possibly consumers.
- **ai_scenarios**: A scenario in `spec/fixtures/ai/scenarios.yml` no longer passes—e.g. tool selection, routing, or policy behavior changed. Update the fixture or the code as intended.
- **ai_adversarial**: A safety or isolation expectation failed. Investigate immediately; do not relax the test unless the threat model has changed and is documented.
- **ai_policy**: Authorization or `allow_record?` behavior changed. Align policy code or spec with intended policy.
- **ai_internal_tooling**: A dev/internal route or response changed. Update the request spec or the controller/view to match.
- **ai_docs**: A required doc was removed or renamed. Restore the file or update `spec/docs/ai_platform_docs_spec.rb` to match the new doc set.
- **demo_seed**: Seed or schema issue; fix seed or DB setup. If the test is skipped (e.g. missing schema), that’s expected in environments without a full test DB.

---

## When to update intentionally

- **Contract change (new field, new version):** Update the corresponding contract spec in `spec/ai/contracts/`, bump any `contract_version` constants, and update consumers (audit, replay, analytics) if they depend on the shape.
- **New scenario or changed expected behavior:** Add or edit entries in `spec/fixtures/ai/scenarios.yml` and ensure the scenario runner’s expectations match.
- **New adversarial case or policy rule:** Add or edit `spec/fixtures/ai/adversarial_scenarios.yml` and the adversarial runner expectations.
- **New required AI doc:** Add an example in `spec/docs/ai_platform_docs_spec.rb` that expects the new file.
- **New internal AI page:** Add a request spec under `spec/requests/dev/` and include it in the `ai_internal_tooling` job and in `rake ai:ci` / `rake ai:ci:internal_tooling`.

---

## CI environment

- **Ruby:** 3.2 (set in workflow).
- **Database:** PostgreSQL with pgvector (service container: `ankane/pgvector:latest`).
- **No external APIs:** All AI tests stub Groq, streaming, and ledger; no real API keys or network calls are required.

---

## Summary

| Goal | Action |
|------|--------|
| Run all AI gates locally | `bin/ci_ai` or `RAILS_ENV=test bundle exec rake ai:ci` |
| Run one gate | `RAILS_ENV=test bundle exec rake ai:ci:<gate>` (e.g. `ai:ci:contracts`) |
| Contract/scenario changed by design | Update the relevant spec or fixture and any version constants |
| Safety/adversarial failure | Treat as regression; fix code or threat model before relaxing test |
