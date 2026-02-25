# AI Agents (Groq + RAG)

Merchant-facing AI chat powered by Groq API with lightweight RAG over the `docs/` folder.

## Endpoint

**POST** `/api/v1/ai/chat`

- **Auth:** `X-API-KEY` header (required). Same as existing API; merchant-scoped.
- **Request body:** `{ "message": "Your question here" }`
- **Response:** `{ "reply": "...", "agent": "...", "citations": [{ "file": "docs/...", "heading": "...", "anchor": "...", "excerpt": "..." }] }`

### Example

```http
POST /api/v1/ai/chat
Content-Type: application/json
X-API-KEY: your_api_key

{ "message": "How do I refund a payment?" }
```

```json
{
  "reply": "According to docs/REFUNDS_API.md...",
  "agent": "support_faq",
  "citations": [
    { "file": "docs/REFUNDS_API.md", "heading": "Endpoint", "anchor": "endpoint", "excerpt": "..." }
  ]
}
```

## Agents

| Agent | Role | Triggered by keywords (examples) |
|-------|------|----------------------------------|
| **support_faq** | Refunds, statuses, API usage, general how-to | Default when no other agent matches |
| **security_compliance** | PCI, PAN, tokenization, logging, webhook signatures | PCI, PAN, CVV, token, webhook signature |
| **developer_onboarding** | Integration: endpoints, idempotency, webhooks | idempotency, integrate, curl, endpoint, API key |
| **operational** | Lifecycle, chargebacks, disputes | status, refund, void, authorize, capture, payment intent |
| **reconciliation_analyst** | Design guidance only | reconciliation, settlement, payout, matching |

**Reconciliation:** This agent clearly states that reconciliation is **not implemented** in the gateway. It only explains what reconciliation would involve and suggests future docs or features.

## RAG (Retrieval)

- **Index:** All `docs/**/*.md` files are parsed into sections by Markdown headings (`#`, `##`, `###`).
- **Search:** Naive keyword scoring over section heading + content; top sections (deduped by file) are retrieved (max 3 sections, ~1200 chars each).
- **Citations:** Every reply includes a `citations` array with `file`, `heading`, `anchor` (slugified heading for deep links), and `excerpt` (first 160 chars of the section). The model is instructed to only claim facts supported by retrieved docs; if not found, it says so and suggests which doc to add/update.

## Environment variables

| Variable | Description | Default |
|---------|-------------|---------|
| `GROQ_API_KEY` | Groq API key (required for real replies) | — |
| `GROQ_BASE_URL` | Groq API base URL | `https://api.groq.com/openai/v1` |
| `GROQ_MODEL` | Model name (overrides default; used as first choice) | `llama-3.3-70b-versatile` |

**Model fallback:** If Groq returns a `model_decommissioned` error (or the message contains "decommissioned"), the client retries exactly once with the next model in the fallback list (e.g. `llama-3.1-8b-instant`). The default model is `llama-3.3-70b-versatile`; set `GROQ_MODEL` to use a different primary model.

## Safety and constraints

- **Read-only:** The AI must not trigger payment actions (authorize, capture, refund, void). It only explains and guides.
- **Merchant scoping:** No other merchants’ data is used or leaked; auth is via `X-API-KEY` and `current_merchant`.
- **No DB writes:** AI endpoints do not write to the database.
- **Context limit:** Max 3 doc sections, each truncated to ~1200 characters.
- **Rate limiting:** Per-merchant limit (20 requests per 60 seconds) for `POST /api/v1/ai/chat`.

## Code layout

- `app/services/ai/groq_client.rb` — Groq API wrapper (Faraday).
- `app/services/ai/router.rb` — Keyword-based agent selection.
- `app/services/ai/agents/` — Base agent + specialist agents (support_faq, security, onboarding, operational, reconciliation).
- `app/services/ai/rag/` — Docs index, Markdown section extractor, retriever.
- `app/controllers/api/v1/ai/chat_controller.rb` — Single chat action: auth, rate limit, RAG, router, agent, JSON response.
