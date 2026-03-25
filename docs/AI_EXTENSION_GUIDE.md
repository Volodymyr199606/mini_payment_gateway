# AI Extension Guide: Adding Agents and Tools

**See also**: [AI_PLATFORM.md](AI_PLATFORM.md) (overview and doc index), [AI_SAFETY_AND_POLICY.md](AI_SAFETY_AND_POLICY.md) (policy and tool restrictions), [AI_SKILL_PLATFORM_V1.md](AI_SKILL_PLATFORM_V1.md) (frozen v1 bounded skill platform).

This guide describes how to add new **agents** and **tools** to the payment gateway AI system using the plugin-style registry pattern. The registries are the single source of truth for discovery, metadata, and capability checks. For **bounded skills**, follow the v1 checklist below so changes stay reviewable and CI-protected.

## Overview

- **Agent registry** (`Ai::AgentRegistry`): Registers agents with metadata (key, class, description, supports_retrieval, supports_memory, **allowed_skill_keys**, etc.). Used by the Router, RequestPlanner, and retrieval/memory flows.
- **Tool registry** (`Ai::Tools::Registry`): Registers deterministic tools with metadata (key, class, description, read_only, cacheable, etc.). Used by the Executor, CachePolicy, and policy layer.
- **Skill registry** (`Ai::Skills::Registry`): Bounded reusable capabilities (`Ai::Skills::BaseSkill` subclasses). Invoked via `Ai::Skills::Invoker` (agent allowlist only; no recursive chains). See [AI_SKILLS_FRAMEWORK.md](AI_SKILLS_FRAMEWORK.md).

Validations run at boot in development/test: duplicate keys, missing classes, and invalid capability combinations (e.g. tools must be `read_only`) cause fail-fast errors.

---

## Adding a New Agent

### 1. Implement the agent class

Create a new agent under `app/services/ai/agents/` that subclasses `Ai::Agents::BaseAgent` (or follows the same interface). Example:

```ruby
# app/services/ai/agents/my_new_agent.rb
module Ai
  module Agents
    class MyNewAgent < BaseAgent
      # ...
    end
  end
end
```

### 2. Register in AgentRegistry

Edit `app/services/ai/agent_registry.rb`:

1. Add the key and class to the **REGISTRY** hash:
   ```ruby
   REGISTRY = {
     # ...
     my_new: Agents::MyNewAgent
   }.freeze
   ```

2. Add a corresponding **DEFINITIONS** entry with required metadata:
   ```ruby
   DEFINITIONS = {
     # ...
     my_new: Agents::AgentDefinition.new(
       key: :my_new,
       class_name: 'Ai::Agents::MyNewAgent',
       description: 'Short description for discovery and debug.',
       supports_retrieval: true,   # false if agent never uses RAG
       supports_memory: true,      # false to skip memory for this agent when standalone
       supports_orchestration: false,
       preferred_execution_modes: [:agent_full],
       debug_label: 'My New Agent'
     )
   }.freeze
   ```

### 3. Metadata fields (agents)

| Field | Required | Description |
|-------|----------|-------------|
| `key` | Yes | Symbol; must match REGISTRY key. |
| `class_name` | Yes | String; fully qualified class name. |
| `description` | No | Short description (debug/UI). |
| `allowed_paths` | No | Array of path names (defaults to all). |
| `supports_retrieval` | No | Default true. If false, RequestPlanner will skip retrieval for this agent. |
| `supports_memory` | No | Default true. If false, memory is skipped when standalone. |
| `supports_orchestration` | No | Default false. |
| `preferred_execution_modes` | No | e.g. `[:agent_full]`, `[:deterministic_only]`. |
| `debug_label` | No | Display name for debug/audit; defaults to key. |

### 4. Wire routing and RAG (if needed)

- **Router**: If the new agent should be chosen by keyword, update `app/services/ai/router.rb` to map keywords to your agent key.
- **RAG**: If the agent uses retrieval, add a policy in `app/services/ai/rag/agent_doc_policy.rb` (allowed/preferred doc paths for the agent key).

### 5. Validation

In development and test, `Ai::AgentRegistry.validate!` runs after initialize. It checks:

- Every REGISTRY key has a class that exists.
- DEFINITIONS keys match REGISTRY keys.
- Each definition has a non-blank `class_name`.

Duplicate keys or missing definitions will raise `ArgumentError` at boot.

---

## Adding a New Tool

### 1. Implement the tool class

Create a new tool under `app/services/ai/tools/` that subclasses `Ai::Tools::BaseTool`. Tools must be **read-only** (no side effects, no writes). Example:

```ruby
# app/services/ai/tools/get_my_resource.rb
module Ai
  module Tools
    class GetMyResource < BaseTool
      def call
        # Validate args, use policy, return { success: true, data: ... } or error
      end
    end
  end
end
```

### 2. Register in Tools::Registry

Edit `app/services/ai/tools/registry.rb`:

1. Add the name and class to the **TOOLS** hash:
   ```ruby
   TOOLS = {
     # ...
     'get_my_resource' => Ai::Tools::GetMyResource
   }.freeze
   ```

2. Add a corresponding **DEFINITIONS** entry:
   ```ruby
   DEFINITIONS = {
     # ...
     'get_my_resource' => ToolDefinition.new(
       key: 'get_my_resource',
       class_name: 'Ai::Tools::GetMyResource',
       description: 'Returns my resource by ID.',
       read_only: true,              # Must be true in current architecture
       requires_merchant_scope: true,
       cacheable: false               # Set true only if safe to cache
     )
   }.freeze
   ```

### 3. Metadata fields (tools)

| Field | Required | Description |
|-------|----------|-------------|
| `key` | Yes | String; must match TOOLS key. |
| `class_name` | Yes | String; fully qualified class name. |
| `description` | No | Short description. |
| `read_only` | Yes | Must be `true`; non-read-only tools are rejected at validation. |
| `requires_merchant_scope` | No | Default true. |
| `allowed_intent_types` | No | Optional restriction. |
| `allowed_agents` | No | Optional; which agents may invoke this tool. |
| `allowed_execution_modes` | No | Optional. |
| `cacheable` | No | If true, CachePolicy will allow caching for this tool. |

### 4. Caching and policy

- **CachePolicy**: `cacheable_tool?` uses the tool definition’s `cacheable` flag. Only set `cacheable: true` for tools whose results are safe to cache (e.g. get_merchant_account, get_ledger_summary).
- **Policy**: `Ai::Policy::Engine#allow_tool?` is used by the Executor; add any tool-specific rules in the policy layer. Registry metadata (e.g. `allowed_agents`) can be used there in the future.

### 5. Intent detection (if user requests invoke the tool)

Wire the tool into the intent detector / follow-up resolver so that user phrases map to the tool name and required args. See `Ai::Followups::IntentResolver` and deterministic tool flow.

### 6. Validation

In development and test, `Ai::Tools::Registry.validate!` runs after initialize. It checks:

- Every TOOLS key has a class that exists.
- DEFINITIONS keys match TOOLS keys.
- Every tool definition has `read_only: true` and non-blank `class_name`.

---

## Adding a v1 skill (bounded platform)

Treat this as a **platform change**, not a one-off class. The stable contract is summarized in [AI_SKILL_PLATFORM_V1.md](AI_SKILL_PLATFORM_V1.md).

1. **Implement** `Ai::Skills::BaseSkill` with a `SkillDefinition` (`DEFINITION`) and `#execute(context:)` returning `Ai::Skills::SkillResult`.
2. **Register** the class in `Ai::Skills::Registry::SKILLS` (explicit hash; no autoload discovery).
3. **Map slots & weight** — `Ai::Skills::ResponseSlots::SKILL_TO_SLOT` and `Ai::Skills::SkillWeights::WEIGHTS` (every registered skill needs both).
4. **Agents** — add the skill key to `Ai::AgentRegistry` `allowed_skill_keys` for each agent that may use it, and **mirror** the same allowlist in `Ai::Skills::AgentProfiles::PROFILES` (must match exactly for v1; `PlatformV1` validates).
5. **Invocation** — extend `InvocationPlanner` / `InvocationCoordinator` only if new phase gates or thresholds are required (keep bounded; no new autonomous loops).
6. **Audit** — usage flows through `Ai::Skills::InvocationResult` and `Ai::Skills::UsageSerializer` (see `SkillMetadataContract`).
7. **Composition** — if the skill participates in multi-skill replies, ensure `ConflictResolver` / `CompositionPlanner` behavior is defined and tested.
8. **Evals & CI** — add YAML scenarios under `spec/fixtures/ai/`, extend skill regression/contract specs (`spec/ai/evals/skills/`, `spec/ai/skills/`, `spec/services/ai/skills/`). See [AI_CI_QUALITY_GATES.md](AI_CI_QUALITY_GATES.md).

**Workflows** (optional multi-step paths): register only in `Ai::Skills::Workflows::Registry`, wire `Selector`/`Executor`, document in `AI_SKILL_PLATFORM_V1.md`. Do not add dynamic or nested workflows.

**Out of scope for v1:** autonomous subagents, recursive planning, runtime skill discovery, arbitrary chaining — see `Ai::Skills::PlatformV1::OUT_OF_SCOPE`.

---

## How the Stack Uses the Registries

- **Router**: Uses `AgentRegistry.all_keys` and `AgentRegistry.fetch(agent_key)`; routing logic can use `AgentRegistry.definition(agent_key)` for capability-aware behavior.
- **RequestPlanner**: Uses `AgentRegistry.definition(agent_key)` for `supports_retrieval` and `supports_memory`. Agents with `supports_retrieval: false` get `skip_retrieval: true`; agents with `supports_memory: false` get `skip_memory: true` when standalone.
- **Executor**: Resolves tools via `Tools::Registry.resolve(tool_name)` and uses `Registry.known?(tool_name)`; caching uses `CachePolicy.cacheable_tool?`, which reads from the tool definition when present.
- **CachePolicy**: `cacheable_tool?(tool_name)` uses `Tools::Registry.definition(tool_name)&.cacheable?` when available, with a fallback list for backward compatibility.
- **Policy / audit / debug**: Can consult registry metadata for allow_tool?, allowed_agents, or display (e.g. debug payload includes `registry_agents` and `registry_tools` when AI_DEBUG is on).

---

## What Is Safe vs Unsafe to Extend

**Safe:**

- Adding a new agent or tool by adding one entry to REGISTRY/DEFINITIONS and one definition.
- Changing description, debug_label, or optional metadata.
- Setting `supports_retrieval` / `supports_memory` to match actual agent behavior.
- Setting `cacheable: true` only for read-only tools whose output is safe to cache.

**Unsafe / avoid:**

- Registering a tool with `read_only: false` (validation will fail).
- Dynamic or arbitrary file-based plugin loading; keep registrations explicit in code.
- Exposing registry internals (e.g. class names, config) to merchant-facing APIs; use only in internal debug/playground when AI_DEBUG is on.

---

## Debug and observability

When `AI_DEBUG` is enabled, the chat debug payload includes:

- `registry_agents`: list of `{ key, label, supports_retrieval, supports_memory }` for each registered agent.
- `registry_tools`: list of `{ key, description, cacheable }` for each registered tool.

This supports the playground and internal drill-down without exposing secrets. Do not add API keys, prompts, or other sensitive data to registry metadata.

---

## Tests

- **Agent registry**: `spec/services/ai/agent_registry_spec.rb` — fetch, all_keys, default_key, and (when added) definition/validate!.
- **Tool registry**: `spec/services/ai/tools/registry_spec.rb` — resolve, known_tools, definition, validate!.
- **RequestPlanner**: Uses agent definitions for retrieval/memory; see `spec/services/ai/performance/request_planner_spec.rb`.
- **CachePolicy**: Uses tool definition for cacheable_tool?; see `spec/services/ai/performance/cache_policy_spec.rb`.

Run the full AI suite after adding or changing agents/tools:

```bash
pnpm exec rspec spec/services/ai/
```
