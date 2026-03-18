# AI Deployment and Release Safety

Deployment hardening and release-safety controls for the AI subsystem. Use this for production deploys, environment configuration, and rolling out new AI features.

## Centralized configuration

- **Feature flags**: `Ai::Config::FeatureFlags` — single source of truth for AI-related toggles. Use these accessors instead of reading `ENV` directly.
- **Runtime config**: `Ai::Config::RuntimeConfig` — numeric/string limits (max memory chars, max sections, cache doc version, etc.).
- **Startup validation**: `Ai::Config::StartupValidator` runs after Rails initialize. In development/test it raises on invalid config; in production it logs errors/warnings and only raises if `AI_CONFIG_STRICT=true`.

## Feature flags (ENV → accessor)

| ENV | Accessor | Default | Notes |
|-----|----------|---------|-------|
| `AI_ENABLED` | `FeatureFlags.ai_enabled?` | true | Master kill switch for AI. |
| `AI_STREAMING_ENABLED` | `FeatureFlags.ai_streaming_enabled?` | false | SSE streaming for chat. |
| `AI_DEBUG` | `FeatureFlags.ai_debug_enabled?` | false | Debug payload in response; see production safety below. |
| `AI_CONTEXT_GRAPH_ENABLED` | `FeatureFlags.ai_graph_retrieval_enabled?` | false | Graph-expanded retrieval. |
| `AI_VECTOR_RAG_ENABLED` | `FeatureFlags.ai_vector_retrieval_enabled?` | false | Hybrid (keyword + vector) retrieval; requires pgvector and embeddings. |
| `AI_ORCHESTRATION_ENABLED` | `FeatureFlags.ai_orchestration_enabled?` | true | Constrained multi-step tool orchestration. |
| `AI_CACHE_BYPASS` | `FeatureFlags.ai_cache_bypass?` | false | Bypass tool/retrieval/memory cache. |
| `AI_INTERNAL_TOOLING_ALLOWED` | `FeatureFlags.internal_tooling_available?` (in prod) | false | In production, enable playground/analytics/health/audits/replay only when set true. In dev/test always true. |
| `AI_DETERMINISTIC_EXPLANATIONS_ENABLED` | `FeatureFlags.deterministic_explanations_enabled?` | true | Use deterministic explanation templates for tool results. |

## Startup validation

- **Debug in production**: If `AI_DEBUG=true` in production, validator adds an **error** unless `AI_DEBUG_ALLOWED_IN_PRODUCTION=true`. In dev/test the app raises; in production it logs and (if `AI_CONFIG_STRICT=true`) raises.
- **Internal tooling in production**: If internal tooling is available in production (e.g. `AI_INTERNAL_TOOLING_ALLOWED=true`), a **warning** is logged. Restrict access by network/auth.
- **Vector retrieval**: When `AI_VECTOR_RAG_ENABLED=true`, a **warning** reminds to ensure pgvector and doc embeddings are backfilled.
- **Streaming**: When `AI_STREAMING_ENABLED=true`, a **warning** reminds to ensure deployment supports SSE.

## Required vs optional AI components

| Component | Critical? | Degraded behavior if unavailable |
|-----------|-----------|-----------------------------------|
| Agent registry, tool registry | Yes | App fails registry validation in dev/test. |
| Request flow (intent, planner, orchestration/agent) | Yes | Core AI chat path. |
| Retrieval (docs) | Yes | Agent path needs at least docs retrieval. |
| Graph retrieval | No | Fallback: use DocsRetriever when graph disabled. |
| Vector retrieval | No | Fallback: use keyword-only when vector disabled or embeddings missing. |
| Streaming | No | Fallback: non-streaming response. |
| Deterministic explanations | No | Fallback: normal composition without template. |
| Playground, analytics, health, audits, replay | No (internal) | Dev routes 404 in production; do not affect merchant-facing flows. |
| Debug payload | No | Omitted when AI_DEBUG disabled. |

## Production safety for internal/dev-only tooling

- **Routes**: `/dev/*` (playground, analytics, health, audits, replay) are behind `DevRoutesConstraint`: they **match only in development and test**. In production the router returns 404 before hitting the controller.
- **Controllers**: Dev controllers use `ensure_dev_only` (render 404 unless `Rails.env.development?` or `Rails.env.test?`). Double guard if route constraint is ever relaxed.
- **Enabling in production**: To expose internal tooling in production (e.g. behind VPN), set `AI_INTERNAL_TOOLING_ALLOWED=true` **and** change the route constraint or add a separate production-safe route with its own auth. Default is off.

## Safe rollout for new AI features

1. **Add a feature flag** in `Ai::Config::FeatureFlags` (and corresponding ENV) for the new behavior.
2. **Default to off** (or to current behavior) so existing deploys are unchanged.
3. **Use the flag** in the relevant service/controller instead of raw ENV.
4. **Document** in this file and in [AI_EXTENSION_GUIDE.md](AI_EXTENSION_GUIDE.md) if it affects extension (e.g. new agent/tool).
5. **Enable per environment** via ENV (e.g. enable in staging first, then production).
6. **Startup validator**: Add a check if the new feature has dependencies (e.g. vector requires embeddings); log warnings or errors as appropriate.

## Config visibility

- **Debug payload** (when `AI_DEBUG` is on): Includes `config_flags` — `FeatureFlags.safe_summary` (no secrets).
- **Health API** (dev/test or when internal tooling allowed): JSON response includes `config_flags` with the same safe summary.
- **Observability**: Use `FeatureFlags.safe_summary` in logs or audit metadata when you need to record which flags were active for a request.

## Strict mode (production)

Set `AI_CONFIG_STRICT=true` in production to make startup validation **raise** on validation errors (e.g. debug enabled without explicit allow). Use when you want the app to refuse to boot with invalid or unsafe config.

## Runtime config (limits)

| ENV | Accessor | Default |
|-----|----------|---------|
| `AI_MAX_MEMORY_CHARS` | `RuntimeConfig.max_memory_chars` | 4000 |
| `AI_MAX_RECENT_MESSAGES` | `RuntimeConfig.max_recent_messages` | 10 |
| `AI_MAX_CONTEXT_CHARS` | `RuntimeConfig.max_context_chars` | 12000 |
| `AI_MAX_RETRIEVED_SECTIONS` | `RuntimeConfig.max_retrieved_sections` | 6 |
| `AI_MAX_CITATIONS` | `RuntimeConfig.max_citations` | 6 |
| `AI_CACHE_DOC_VERSION` | `RuntimeConfig.cache_doc_version` | v1 |

These are used by memory budgeter, context budgeter, and cache keys. Optional; app runs with defaults if unset.
