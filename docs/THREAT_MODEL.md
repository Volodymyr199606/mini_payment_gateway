# Threat Model

Practical threat model for the mini payment gateway: multi-tenant API + dashboard + webhooks + AI subsystem. Aligned with the current codebase.

---

## 1. Assets

| Asset | Sensitivity | Notes |
|-------|-------------|-------|
| **Merchant account data** | High | Name, email, status. Used for auth and display. |
| **API keys** | Critical | Only bcrypt digest stored. Plain key shown once at create/regeneration. Unauthorized use = full API access. |
| **Session state** | High | `session[:merchant_id]` controls dashboard access. Session fixation/hijack = full dashboard access. |
| **Payment intents / transactions / ledger** | High | Financial state. Regulated, audit-critical. |
| **Customer / payment method metadata** | Medium | Token, last4, brand, exp (no PAN). PCI-adjacent. |
| **Webhook secret** | Critical | HMAC key for inbound verification. Compromise = forged webhooks accepted. |
| **Webhook event payloads** | Medium | May contain PI ids, event types. Integrity matters. |
| **Audit logs (payment)** | High | Immutability and completeness for disputes. |
| **AI request audits** | Medium | Metadata (agent_key, tool_names, latency, etc.). No prompts/secrets by design. Sensitive for debugging. |
| **AI debug metadata** | Medium | Retriever context, section ids when AI_DEBUG=1. Must not leak prompts/keys. |
| **Docs corpus** | Low | Internal platform docs in RAG. Source-composition trust. |
| **Internal/dev tooling** | High | Playground, analytics, health, replay. 404 in production via DevRoutesConstraint; no auth in dev. |

---

## 2. Trust Boundaries

| Boundary | Inside | Outside |
|----------|--------|---------|
| **Public API** | Authenticated merchant (X-API-KEY), scoped data | Unauthenticated, other tenants |
| **Dashboard** | Session-authenticated merchant | Unauthenticated, other tenants |
| **Webhook ingress** | Signature-verified processor events | Forged or replayed payloads |
| **Internal/dev tooling** | Dev/test env only (DevRoutesConstraint) | Production (blocked), external users |
| **AI subsystem** | Policy engine, merchant context, tool executor | User prompts, RAG context, external LLM (Groq) |
| **Background jobs** | Webhook delivery, AI summary refresh | Queue, external HTTP |
| **Cache** | Merchant-scoped keys (tools, retrieval) | Cross-tenant leakage if keys collide |
| **Provider / sandbox** | Simulated or Stripe sandbox | Production Stripe, live cards |
| **AI provider** | Groq API (when used) | Third-party LLM, prompt leakage |

---

## 3. Attack Surfaces

| Surface | Auth | Key risks |
|---------|------|-----------|
| **API endpoints** | X-API-KEY | Broken auth, cross-tenant access, param injection |
| **Dashboard forms / pages** | Session | CSRF, session hijack, XSS |
| **Webhook endpoint** | HMAC | Forged events, replay, merchant_id spoof in payload |
| **AI chat (API)** | X-API-KEY | Prompt injection, tool abuse, cross-tenant via follow-up |
| **AI chat (dashboard)** | Session | Same as above + session issues |
| **Replay / debug / internal** | None (dev) or env-gated | Sensitive metadata exposure, replay across tenants |
| **Background jobs** | Internal | Malformed input, external HTTP failures |
| **Logs / observability** | Internal | Secret leakage, over-logging |
| **AI analytics / health** | None (dev) | Aggregate or per-merchant metadata exposure |
| **AI playground** | None (dev) | Arbitrary message, merchant selection |

---

## 4. Threat Categories (STRIDE-style)

### Spoofing / broken auth
- **API**: Invalid or missing X-API-KEY → 401. BCrypt comparison; timing-safe via BCrypt.
- **Dashboard**: Session-based; protect_from_forgery. Sign-in via email/password or API key.
- **Webhook**: No merchant auth; relies on signature. Compromised secret = full spoof.
- **Dev tooling**: No auth. Relies on DevRoutesConstraint (dev/test only) and network isolation.

### Tampering
- **Payment flows**: State machine in services (Authorize, Capture, Refund, Void). No direct DB writes from API params.
- **Webhook**: HMAC over raw body. Tampering invalidates signature.
- **Idempotency**: Fingerprint (v1 canonical + legacy) compared on cache hit; same key with different logical payload returns **409** (see `docs/IDEMPOTENCY.md`).
- **Ledger**: Written by services; no user-controlled ledger writes.
- **Audit logs**: Append-only; no update/delete from normal flows.

### Repudiation
- **Audit trail**: Payment actions logged (AuditLogService, Auditable). AI requests logged (AiRequestAudit).
- **Idempotency**: Records link request to response for dispute resolution.
- **No cryptographic signing** of audit records; integrity relies on DB and access control.

### Information disclosure
- **Cross-tenant**: All queries scoped by `current_merchant` or `merchant_id`. Policy engine validates record ownership.
- **AI tools**: `allow_record?` after fetch. Deterministic data gated by policy.
- **Debug**: AI_DEBUG gates extra payload; policy rejects prompt/api_key in debug.
- **Logs**: SafeLogHelper redacts tokens/keys. Structured logging.
- **Cache**: Keys include merchant_id (tools) or session_id (memory); retrieval keys use message+agent+doc_version (no tenant in key — retrieval is stateless by design).

### Denial of service
- **API**: Category-based rate limits on `Api::V1::BaseController` (`ApiRateLimitable`); merchant-scoped buckets; IP for webhook/public merchant POST. See `docs/API_RATE_LIMITING.md`.
- **AI**: 20 req/60s per merchant (dashboard + API). Enforced in controllers.
- **Webhook**: No rate limit on processor endpoint. Replay of valid signed payload → duplicate DB rows.
- **Background jobs**: Inline in development; queue in production. No job rate limit.

### Elevation of privilege
- **No RBAC**: Single merchant role. API key or session = full merchant scope.
- **Provider adapter**: ProviderRegistry builds adapter from config. No runtime elevation.
- **AI policy**: Engine gates tools, orchestration, memory, follow-up. Bypass = code defect.

---

## 5. Payment/Webhook-Specific Threats

| Threat | Current state |
|--------|---------------|
| **Replay of idempotent request** | Same key returns cached response. Intended. |
| **Reuse idempotency key with different params** | Returns cached response without checking request_hash. **Gap.** |
| **Forged webhook** | HMAC verification; reject if invalid. |
| **Webhook replay** | Each POST creates new WebhookEvent. No idempotency by provider_event_id. Duplicate events possible. |
| **merchant_id in webhook payload** | Taken from normalized payload. Attacker with valid signature could target specific merchant (need secret). |
| **Inconsistent ledger** | Ledger entries created by services in same transaction as payment actions. |
| **Unsafe state transitions** | Services validate state (e.g. capture requires authorized). |
| **Cross-tenant transaction access** | All access via `current_merchant.payment_intents`, etc. |
| **Refund/capture misuse** | RefundService validates captured state, amount. |

---

## 6. AI-Specific Threats

| Threat | Current state |
|--------|---------------|
| **Cross-tenant via tools** | Tools receive merchant_id from context. Executor and Authorization validate ownership. |
| **Cross-tenant via follow-up** | allow_followup_inheritance? revalidates entity ownership. |
| **Prompt injection into tool path** | IntentDetector uses constrained patterns. No arbitrary tool invocation from free text. |
| **Prompt injection into RAG** | Docs context influences answer; no direct tool/DB writes from prompt. |
| **Unsafe replay** | Replay uses audit.merchant_id; no cross-tenant. Replay does not re-run agent, only orchestration. |
| **Debug exposure** | AI_DEBUG + allow_debug_exposure? blocks prompt/api_key. StartupValidator blocks AI_DEBUG in prod unless ALLOWED. |
| **Audit metadata leakage** | DetailPresenter whitelist (SAFE_KEYS). No prompt, no keys. |
| **Deterministic tool misuse** | Tools read-only. Registry enforces. |
| **Policy engine bypass** | Engine is central; no intentional bypass. |
| **Analytics / health** | Merchant-scoped filters. Dev/test only. |
| **Dev pages in production** | DevRoutesConstraint → 404. |
| **Cache key collision** | Retrieval keys: message+agent+graph/vector+doc_version. No merchant. Low collision risk; same query = same cache by design. Tool keys: merchant_id+tool+args. |
| **Stale follow-up memory** | Memory is session-scoped. Topic change can trigger refresh. |

---

## 7. Internal/Dev Tooling Threats

| Component | Protection | Residual risk |
|-----------|------------|---------------|
| **DevRoutesConstraint** | Routes return 404 in production | Relies on env; misconfiguration could expose |
| **Auth on dev routes** | None | In dev, anyone with network access can use |
| **Replay** | Uses audit data only; merchant_id from audit | Replay runs as internal; no user-supplied merchant |
| **Audit drill-down** | SAFE_KEYS whitelist | No prompts/secrets in persisted audit |
| **AI playground** | Merchant picker; runs as selected merchant | In dev only; no prod access |
| **AI analytics / health** | Merchant filter, dev only | Aggregate data could hint at usage |
| **Production disablement** | DevRoutesConstraint | Document that /dev/* must never be enabled in prod |

---

## 8. Summary Table

| Threat | Subsystem | Mitigation | Residual | Priority |
|--------|-----------|------------|----------|----------|
| Invalid API key | API | BCrypt, 401 | Low | — |
| Cross-tenant data access | API, dashboard | current_merchant scoping | Low | — |
| Webhook forgery | Webhooks | HMAC verify | Low | — |
| Idempotency key reuse, different params | Payments | 409 + audit log | Medium | Low |
| General API rate limit | API | None | Medium | Medium |
| Webhook rate limit | Webhooks | None | Low | Low |
| AI rate limit | AI | 20/60s | Low | — |
| Dev routes in prod | Internal | DevRoutesConstraint | Low | — |
| AI_DEBUG in prod | AI | StartupValidator | Low | — |
| Debug payload secrets | AI | allow_debug_exposure? | Low | — |
| Session fixation | Dashboard | Default Rails | Low | — |
| Webhook replay / duplicates | Webhooks | None | Low | Low |
