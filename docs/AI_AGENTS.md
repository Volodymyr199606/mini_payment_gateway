# AI Agents (Groq + RAG)

Merchant-facing AI chat powered by Groq API with lightweight RAG over the `docs/` folder.

## Endpoint

**POST** `/api/v1/ai/chat`

- **Auth:** `X-API-KEY` header (required). Same as existing API; merchant-scoped.
- **Request body:** `{ "message": "Your question here" }`
- **Response:** `{ "reply": "...", "agent": "...", "citations": [...], "data": null | {...} }`  
  For the reporting agent, `data` contains the ledger summary used for the reply; for other agents `data` is `null`.

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

| Agent | Role | Triggered by |
|-------|------|---------------|
| **reporting_calculation** | Totals from ledger (charges, refunds, fees, net) for a time range | Phrases: "how much", "last 7 days", "last week", "this month", "last month", "yesterday", "refund volume", "net balance", "total charges/refunds/fees"; or words: total, sum, spent, fees, net, balance |
| **support_faq** | Refunds, statuses, API usage, general how-to | Default when no other agent matches |
| **security_compliance** | PCI, PAN, tokenization, logging, webhook signatures | PCI, PAN, CVV, token, webhook signature |
| **developer_onboarding** | Integration: endpoints, idempotency, webhooks | idempotency, integrate, curl, endpoint, API key |
| **operational** | Lifecycle, chargebacks, disputes | status, refund, void, authorize, capture, payment intent |
| **reconciliation_analyst** | Design guidance only | reconciliation, settlement, payout, matching |

**Reconciliation:** This agent clearly states that reconciliation is **not implemented** in the gateway. It only explains what reconciliation would involve and suggests future docs or features.

### Reporting / Calculation agent

The **reporting_calculation** agent answers “how much” / totals / volume / fees / refunds questions using **real ledger data** (no LLM arithmetic). It:

1. Parses the user’s timeframe with a deterministic Ruby parser (see **Time-range parser** below).
2. Calls `Reporting::LedgerSummary` with `merchant_id` from auth, `from`/`to`, optional `currency`, optional `group_by`.
3. Formats a human reply from the tool output (totals in dollars, timeframe, disclaimer).

**Sign convention (ledger summary):**

- Ledger: charge entries positive, refund entries negative.
- Output: `charges_cents`, `refunds_cents` (displayed as positive), `fees_cents` (signed: positive = merchant pays).
- **Net:** `net_cents = charges_cents - refunds_cents - fees_cents` (merchant view: receive charges, pay refunds and fees).

**Disclaimer in reply:** “Totals are based on ledger entries created on capture/refund (not authorize/void).”

**Time-range parser** (`Ai::TimeRangeParser`):

- Supported phrases: `"today"`, `"yesterday"`, `"last 7 days"`, `"last week"`, `"this month"`, `"last month"`.
- Timezone: **America/Los_Angeles**. “Last week” = previous Monday 00:00 to Sunday 23:59:59.
- Max range: **365 days**; larger ranges return 400 with a helpful message.

**Example (reporting):**

```http
POST /api/v1/ai/chat
Content-Type: application/json
X-API-KEY: your_api_key

{ "message": "How much in fees last 7 days?" }
```

```json
{
  "reply": "For the last 7 days (2025-02-05 to 2025-02-11): Fees: $1.00. Totals are based on ledger entries created on capture/refund (not authorize/void).",
  "agent": "reporting_calculation",
  "citations": [],
  "data": {
    "currency": "USD",
    "from": "2025-02-05T08:00:00.000Z",
    "to": "2025-02-11T07:59:59.999Z",
    "totals": { "charges_cents": 0, "refunds_cents": 0, "fees_cents": 100, "net_cents": -100 },
    "counts": { "captures_count": 0, "refunds_count": 0 }
  }
}
```

## RAG (Retrieval)

- **Index:** All `docs/**/*.md` files are parsed into sections by Markdown headings (`#`, `##`, `###`).
- **Agent-aware retrieval:** The message is routed to an agent first; then retrieval is restricted and boosted by that agent’s doc policy (`AgentDocPolicy`). Each agent has an allowed list of docs (and optionally preferred docs for scoring boost). This reduces irrelevant citations and improves answers (e.g. “authorize vs capture” gets context from PAYMENT_LIFECYCLE, ARCHITECTURE).
- **Search:** Naive keyword scoring over section heading + content; candidates are filtered by the agent’s allowed docs, preferred docs get a score boost; top sections (deduped by file) are retrieved (max 3 sections, ~1200 chars each).
- **Citations:** Every reply includes a `citations` array with `file`, `heading`, `anchor` (slugified heading for deep links), and `excerpt` (first 160 chars of the section). The model is instructed to only claim facts supported by retrieved docs; if not found, it says so and suggests which doc to add/update.

## Environment variables

| Variable | Description | Default |
|---------|-------------|---------|
| `GROQ_API_KEY` | Groq API key (required for real replies) | — |
| `GROQ_BASE_URL` | Groq API base URL | `https://api.groq.com/openai/v1` |
| `GROQ_MODEL` | Model name (overrides default; used as first choice) | `llama-3.3-70b-versatile` |

**Model fallback:** If Groq returns a `model_decommissioned` error (or the message contains "decommissioned"), the client retries exactly once with the next model in the fallback list (e.g. `llama-3.1-8b-instant`). The default model is `llama-3.3-70b-versatile`; set `GROQ_MODEL` to use a different primary model.

## AI Configuration

| Variable | Description | Default |
|---------|-------------|---------|
| `AI_CONTEXT_GRAPH_ENABLED` | Use graph-expanded retrieval (seed sections + parent/next/linked sections). | off |
| `AI_VECTOR_RAG_ENABLED` | Use hybrid retrieval (keyword + vector similarity). Requires pgvector and backfilled embeddings. | off |
| `AI_DEBUG` | Include debug panel in AI chat response (retriever name, seed/expanded/included section ids, context budget, summary flags). Dev only. | off |
| `EMBEDDING_API_KEY` | API key for embeddings (backfill and hybrid retrieval). OpenAI-compatible endpoint. | — |
| `OPENAI_API_KEY` | Fallback if `EMBEDDING_API_KEY` not set; used for embedding backfill and hybrid retrieval. | — |

**Copy-paste (development):**

```bash
export GROQ_API_KEY="your_groq_key"
# Optional: graph retrieval
export AI_CONTEXT_GRAPH_ENABLED=true
# Optional: hybrid (keyword + vector) — requires pgvector + backfill
export AI_VECTOR_RAG_ENABLED=true
export EMBEDDING_API_KEY="your_openai_or_compatible_key"
# Optional: debug panel in chat UI
export AI_DEBUG=true
```

### pgvector and hybrid retrieval

- **Requirement:** The [pgvector](https://github.com/pgvector/pgvector#installation) PostgreSQL extension must be installed before running the migration that creates `doc_section_embeddings`.
- **Backfill:** Creates embeddings for all Markdown doc sections (from `docs/`), stores them in `doc_section_embeddings`. Run after setting `EMBEDDING_API_KEY` or `OPENAI_API_KEY`:

  ```bash
  rake ai:backfill_doc_embeddings
  ```

- **What it does:** Reads sections from the doc graph (file + heading + content), calls the embedding API per section, upserts into `doc_section_embeddings` (section_id, vector, updated_at). Used by hybrid retrieval for similarity search.
- **Test hybrid retrieval:** Set `AI_VECTOR_RAG_ENABLED=true` (and leave `AI_CONTEXT_GRAPH_ENABLED` off to use hybrid instead of graph). Chat will merge keyword and vector results and rerank with RRF.
- **Runbook:** See [docs/runbooks/AI_EMBEDDINGS_RUNBOOK.md](runbooks/AI_EMBEDDINGS_RUNBOOK.md) for prerequisites, backfill, smoke task (`rake ai:smoke_hybrid`), and troubleshooting.

## Safety and constraints

- **Read-only:** The AI must not trigger payment actions (authorize, capture, refund, void). It only explains and guides.
- **Merchant scoping:** No other merchants’ data is used or leaked; auth is via `X-API-KEY` and `current_merchant`.
- **No DB writes:** AI endpoints do not write to the database.
- **Context limit:** Max 3 doc sections, each truncated to ~1200 characters.
- **Rate limiting:** Per-merchant limit (20 requests per 60 seconds) for `POST /api/v1/ai/chat`.

## Code layout

- `app/services/ai/groq_client.rb` — Groq API wrapper (Faraday).
- `app/services/ai/router.rb` — Phrase/keyword-based agent selection (reporting phrases first).
- `app/services/ai/agents/` — Base agent + specialist agents (support_faq, security, onboarding, operational, reconciliation, **reporting_calculation**).
- `app/services/ai/time_range_parser.rb` — Deterministic parser for “today”, “last 7 days”, “last week”, etc. (America/Los_Angeles, max 365 days).
- `app/services/reporting/ledger_summary.rb` — Ledger totals by merchant and time range (charges, refunds, fees, net, counts, optional breakdown).
- `app/helpers/ai_money_helper.rb` — Format cents as `"$12.34"`.
- `app/services/ai/rag/` — Docs index, Markdown section extractor, retriever, **agent_doc_policy** (per-agent allowed/preferred docs).
- `app/controllers/api/v1/ai/chat_controller.rb` — Single chat action: auth, rate limit, RAG, router, agent, JSON response (includes `data` for reporting agent).

### Context graph (intended API)

**Production:** Use **`Ai::Rag::ContextGraph`** as the single canonical graph for RAG. It reads from `docs/`, builds nodes (section id = `file#anchor`) with parent/child, prev/next, and cross-doc links, and is used by DocsRetriever, GraphExpandedRetriever, and HybridRetriever.

- **Entry point:** `Ai::Rag::ContextGraph.instance` (singleton; reloads in development when docs change). In tests, call `Ai::Rag::ContextGraph.reset!` before examples that need a fresh graph.
- **API:** `#node(section_id)` → node hash; `#expand(seed_ids, max_hops:, max_nodes:)` → expanded section id list; `#nodes` → array of nodes.

**Test-only:** `Ai::ContextGraph::Builder` and `Ai::ContextGraph::Graph` (under `app/services/ai/context_graph/`) build a graph from in-memory sections for unit tests. They are not used in production. Production code should use only `Ai::Rag::ContextGraph`.
