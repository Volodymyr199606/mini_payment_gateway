# Security Review

Practical security review and hardening plan for the mini payment gateway. Complements [THREAT_MODEL.md](THREAT_MODEL.md) and [SECURITY.md](SECURITY.md).

---

## 1. Current Mitigations (Verified in Codebase)

### Authentication
| Control | Implementation |
|---------|----------------|
| API key auth | `ApiAuthenticatable`, `Merchant.find_by_api_key` (BCrypt) |
| API key storage | bcrypt digest only; plain key shown once at create/regenerate |
| Dashboard auth | Session `session[:merchant_id]`; sign-in via email/password or API key |
| CSRF | `protect_from_forgery with: :exception` on dashboard and dev |

### Authorization (tenant isolation)
| Control | Implementation |
|---------|----------------|
| Merchant scoping | All data access via `current_merchant.payment_intents`, `customers`, etc. |
| Record ownership | `find` raises RecordNotFound if ID not in scope |
| AI policy | `Ai::Policy::Authorization` + `Engine`; `allow_tool?`, `allow_record?`, `allow_followup_inheritance?` |
| AI context | `merchant_id` in context; tools and orchestration require it |

### Webhooks
| Control | Implementation |
|---------|----------------|
| Signature verification | `provider.verify_webhook_signature(payload, headers)` before processing |
| HMAC | `WebhookSignatureService.generate_signature` (SHA256) |
| Secure compare | `ActiveSupport::SecurityUtils.secure_compare` for verification |
| Secret config | `WEBHOOK_SECRET` env or credentials; dev default documented |

### Idempotency
| Control | Implementation |
|---------|----------------|
| Key scoping | `merchant_id` + `idempotency_key` + `endpoint` |
| Request hash | Stored for audit; **not compared on cache hit** (gap) |
| Response caching | Same key returns cached body/status |

### Audit and logging
| Control | Implementation |
|---------|----------------|
| Payment audit | `AuditLogService`, `Auditable` concern |
| AI audit | `AiRequestAudit`, `AuditTrail::RecordBuilder` |
| Safe logging | `SafeLogHelper.sanitize_*`, token redaction |
| Request ID | `RequestIdMiddleware` |

### AI-specific
| Control | Implementation |
|---------|----------------|
| Policy engine | Central `Engine`; tool, orchestration, memory, follow-up, debug gates |
| Debug exposure | `allow_debug_exposure?` blocks prompt/api_key; AI_DEBUG env |
| Startup validation | `Ai::Config::StartupValidator` blocks AI_DEBUG in prod unless ALLOWED |
| Tool read-only | Registry `read_only: true`; no write tools |
| Cache keys | `CacheKeys.tool(merchant_id:, ...)`, `retrieval(message:, agent_key:, ...)` |
| Follow-up inheritance | `allow_followup_inheritance?` revalidates entity ownership |

### Internal tooling
| Control | Implementation |
|---------|----------------|
| Dev routes | `DevRoutesConstraint`: `Rails.env.development? || Rails.env.test?` → 404 otherwise |
| Audit presenter | `DetailPresenter` SAFE_KEYS whitelist; no prompts, no keys |
| Replay | Uses `audit.merchant_id`; no user-supplied merchant |

### Payment core
| Control | Implementation |
|---------|----------------|
| State machine | Services validate state (e.g. capture requires authorized) |
| Ledger | Written in same transaction as payment actions |
| No PAN | Only token, last4, brand, exp stored |

---

## 2. Identified Gaps and Residual Risks

### High priority

**Idempotency: no request_hash check on cache hit**  
- **Issue**: Same idempotency key with different request params returns cached response. Standard semantics (Stripe, etc.) is 409 Conflict when params differ.  
- **Location**: `IdempotencyService`  
- **Impact**: Client could receive wrong response; audit trail would show mismatched request/response.  
- **Recommendation**: On cache hit, compare `Digest::SHA256.hexdigest(@request_params.to_json)` to `existing_record.request_hash`. If different, return 409 with clear message.

### Medium priority

**General API rate limiting not enforced**  
- **Issue**: `RateLimiterService` exists but is not called by any controller. `ApiRequestStat` records 429 only if something returns 429; nothing does.  
- **Impact**: DoS via high request volume per API key.  
- **Recommendation**: Add `before_action` in `Api::V1::BaseController` (or per-controller) that calls `RateLimiterService` and returns 429 when limited.

**Webhook secret boot validation**  
- **Issue**: Default dev secret used if unset. No boot-time check that production has explicit `WEBHOOK_SECRET`.  
- **Impact**: Deploy with default secret = forged webhooks accepted.  
- **Recommendation**: In production, fail or warn loudly if `webhook_secret == 'default_webhook_secret_for_development_only'` or blank.

### Lower priority

**Security headers**  
- Rails default: `X-Frame-Options: SAMEORIGIN`. No explicit CSP, HSTS config.  
- **Recommendation**: Consider CSP, HSTS for production (config depends on deployment).

**Webhook replay / duplicate events**  
- No idempotency by `provider_event_id`. Same event POSTed twice creates two `WebhookEvent` rows.  
- **Impact**: Duplicate processing if downstream does not dedupe.  
- **Recommendation**: Optional uniqueness constraint or lookup before create; document expected processor behavior.

**Dev tooling auth**  
- In dev, `/dev/*` has no auth. Relies on network isolation.  
- **Recommendation**: Document that dev tooling must never be exposed to untrusted networks; consider optional HTTP basic auth in dev.

---

## 3. Prioritized Hardening Plan

| Priority | Action | Effort | Impact |
|----------|--------|--------|--------|
| **High** | Add request_hash comparison in IdempotencyService cache hit path; return 409 when params differ | Low | Correct idempotency semantics; prevents wrong cached response |
| **Medium** | Wire RateLimiterService into API base controller; return 429 when limit exceeded | Low | Reduces DoS risk |
| **Medium** | Add boot-time validation: reject/warn when production uses default webhook secret | Low | Prevents accidental deployment with weak secret |
| **Low** | Add CSP / HSTS config for production | Medium | Defense in depth |
| **Low** | Document webhook deduplication expectations; optionally add provider_event_id uniqueness | Low–Medium | Reduces duplicate event risk |
| **Low** | Optional: HTTP basic auth for /dev/* in development | Low | Extra layer for dev exposure |

---

## 4. Risk Matrix Summary

| Threat | Affected subsystem | Current mitigation | Residual risk | Priority | Recommended action |
|--------|--------------------|--------------------|---------------|----------|--------------------|
| Idempotency param mismatch | Payments | None | Medium | High | Compare request_hash; return 409 |
| API DoS | API | None | Medium | Medium | Enforce RateLimiterService |
| Default webhook secret in prod | Webhooks | None | Medium | Medium | Boot validation |
| Cross-tenant access | API, dashboard | Merchant scoping | Low | — | Maintain discipline |
| Webhook forgery | Webhooks | HMAC | Low | — | Keep secret safe |
| AI cross-tenant | AI | Policy engine | Low | — | — |
| Debug leakage | AI | allow_debug_exposure? | Low | — | — |
| Dev routes in prod | Internal | DevRoutesConstraint | Low | — | Document, verify |
| Webhook duplicates | Webhooks | None | Low | Low | Document; optional dedupe |

---

## 5. Developer Guidance

### Safe patterns

1. **Tenant boundaries**  
   Always scope by `current_merchant` or `merchant_id` from authenticated context. Never use user-supplied merchant_id for authorization.

2. **New API endpoints**  
   - Inherit from `Api::V1::BaseController` (gets API key auth).  
   - Use `current_merchant.payment_intents.find(id)`-style access, not `PaymentIntent.find(id)`.

3. **New AI tools**  
   - Register in `Ai::Tools::Registry` with `read_only: true`.  
   - Pass `merchant_id` in context; validate record ownership with `Policy::Authorization#allow_record?` before returning data.  
   - Use `CacheKeys.tool(merchant_id:, tool_name:, args:)` for caching.

4. **New dashboard routes**  
   - Use `Dashboard::BaseController`; ensure `protect_from_forgery`.  
   - Use `current_merchant` for all data access.

5. **Secrets and debug**  
   - Never log API keys, tokens, or passwords. Use `SafeLogHelper`.  
   - Debug payloads must not contain prompts or keys; policy checks this.  
   - Do not enable AI_DEBUG in production without explicit ALLOWED flag.

### Unsafe changes to avoid

1. **Bypassing policy**  
   Do not skip `Policy::Engine` or `Authorization` for AI tool results or composition.

2. **Global finds**  
   Never `PaymentIntent.find(params[:id])` without merchant scope. Use `current_merchant.payment_intents.find`.

3. **User-controlled merchant_id**  
   Do not use `params[:merchant_id]` for authorization. Use session or API auth context.

4. **Webhook without verify**  
   Never process webhook payload before signature verification.

5. **Idempotency without key**  
   For mutating payment operations, support idempotency_key and use IdempotencyService.

6. **Dev routes without constraint**  
   New internal tools must live under `constraints(DevRoutesConstraint)`.

### Before shipping AI-related changes

- [ ] New tools are read-only and in registry.  
- [ ] Policy engine is used for ownership checks.  
- [ ] Cache keys include merchant_id where data is tenant-specific.  
- [ ] No prompt or API key in debug payload.  
- [ ] Follow-up inheritance revalidates entity ownership.  
- [ ] Adversarial / contract tests still pass.

### Before shipping payment/webhook changes

- [ ] All access is merchant-scoped.  
- [ ] State transitions are validated in services.  
- [ ] Idempotency is handled for mutations.  
- [ ] Webhook verification is unchanged or strengthened.  
- [ ] Audit logging covers new actions.

---

## 6. Optional Supporting Checks

- **Checklist doc**: `docs/SECURITY_CHECKLIST.md` for pre-merge review of security-sensitive changes (can be added if team wants a formal checklist).  
- **Boot warning**: Add to `config/initializers` or `Ai::Config::StartupValidator` a check that production does not use default webhook secret.  
- **CI reference**: Link `SECURITY_REVIEW.md` and `THREAT_MODEL.md` from CI/docs quality gates so reviewers know where to look.
