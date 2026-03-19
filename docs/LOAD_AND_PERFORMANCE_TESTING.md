# Load and performance testing

This project includes a **lightweight Ruby perf harness** under `perf/lib/` (no k6/JMeter). It drives the real Rails stack via `ActionDispatch::Integration::Session` and optional `Rack::MockRequest` for webhooks, measures wall-clock latency per iteration, and writes reports under `tmp/perf/`.

## Goals

- **Repeatable**: deterministic payment processor (`perf` stubs), **no real Groq** and **no outbound webhook HTTP** on default runs.
- **Merchant-scoped**: scenarios create their own merchant/API key/customer graph (`MiniPaymentGatewayPerf::World`).
- **Practical metrics**: runs, errors, median/p95 ms, throughput (successful requests / wall time), optional `cache_state` and `notes`.

## What is *not* covered

- Production load testing, SLA proof, or provider sandbox benchmarks (Stripe/Groq live).
- Saturating the DB or cluster; default iteration counts are modest.
- Assertions on absolute latency (machine-dependent).

Optional future modes could document `PERF_LIVE_GROQ=1` etc.; they are **not** implemented by default.

## Scenarios (by group)

| Group | Scenario | What it measures |
|-------|----------|------------------|
| **payments** | `payment_create_intent` | `POST /api/v1/payment_intents` |
| | `payment_authorize` | Create PI + `POST .../authorize` |
| | `payment_capture` | Create + authorize + `POST .../capture` |
| | `payment_refund_partial` | Captured PI + `POST .../refunds` (partial) |
| | `payment_list_intents` | `GET /api/v1/payment_intents` after seeding extra rows |
| | `payment_list_transactions` | Session sign-in + `GET /dashboard/transactions` |
| | `payment_list_ledger` | Session sign-in + `GET /dashboard/ledger` |
| | `payment_authorize_idempotent_warm` | Second `POST authorize` with same `idempotency_key` (cached path) |
| **webhooks** | `webhook_inbound_signed` | HMAC verify + persist + stubbed delivery job |
| | `webhook_inbound_duplicate` | Same fixed `event_id` replayed (each request still persists; **no dedup** in DB) |
| **ai** | `ai_api_chat_operational` | `POST /api/v1/ai/chat` (router, retrieval cache, agent, Groq **stubbed**) |
| | `ai_api_chat_same_message_cold_warm` | Half iterations with `Rails.cache.clear` before each call vs half warm (see notes column) |
| | `ai_dashboard_tool_orchestration` | Dashboard session + CSRF + `POST /dashboard/ai/chat` (tool/orchestration path; Groq stubbed) |
| **internal** | `dev_ai_health_json` | `GET /dev/ai_health` as JSON (**development/test only**; skipped in other envs) |

## Stubs (default runs)

`MiniPaymentGatewayPerf::Stubs.install!` (invoked by `rake perf:*`):

- **`Payments::ProviderRegistry`**: `DeterministicProvider` (always-success authorize/capture/refund/void; webhook verify aligned with `WebhookSignatureService`).
- **`Ai::GroqClient`**: fixed short reply (no network).
- **`WebhookDeliveryJob.perform_later`**: no-op (no outbound HTTP).
- **AI rate limits**: bypassed on dashboard/API AI controllers so `PERF_ITERATIONS` can exceed 20/min per merchant.

## How to run

From the app root (Bundler):

```bash
bundle exec rake perf:run
bundle exec rake perf:payments
bundle exec rake perf:webhooks
bundle exec rake perf:ai
bundle exec rake perf:internal
```

Or:

```bash
bin/load_test              # same as perf:run
bin/load_test payments
bin/load_test ai
```

### Environment variables

| Variable | Meaning |
|----------|---------|
| `PERF_ITERATIONS` | Iterations per scenario (default `30`) |
| `PERF_CONCURRENCY` | Threads per scenario (`1` = sequential; work split across threads) |
| `ONLY` | Comma-separated scenario names (e.g. `ONLY=payment_capture,webhook_inbound_signed`) |

Use **`development`** or **`test`** with a prepared database (`db:prepare`). **`production`** is discouraged; dev routes and stubs are not meant for prod.

## Reports

Each run creates `tmp/perf/run_YYYYMMDD_HHMMSS/` with:

- **`results.json`**: `recorded_at`, `meta` (env, iterations, concurrency, pid), `scenarios[]` rows.
- **`summary.md`**: Markdown table for quick comparison.

Row fields include: `scenario`, `runs`, `errors`, `min_ms`, `max_ms`, `mean_ms`, `median_ms`, `p95_ms`, `duration_sec`, `throughput_rps`, `cache_state`, `notes`.

## Interpreting results

- **Trend over time** on the same machine/DB matters more than absolute ms.
- **errors > 0**: inspect stderr for `[perf]` lines; check CSRF/session for dashboard paths, DB state, and `WEBHOOK_SECRET` consistency for webhook HMAC.
- **`ai_api_chat_same_message_cold_warm`**: `notes` lists separate cold vs warm medians/p95; the row’s aggregate stats mix both phases.
- **`payment_authorize_idempotent_warm`**: times **only** the idempotent repeat authorize call.

### Rough “good enough” (indicative only)

On a typical dev laptop with SQLite/Postgres and small data: payment API mutations often land in **tens–low hundreds of ms**; list endpoints after seeding may be **higher**. AI paths include retrieval, audits, and optional jobs (inline in development)—expect **hundreds of ms to a few seconds** depending on corpus and flags. Treat these as **order-of-magnitude**, not SLAs.

## Implementation layout

- `perf/lib/mini_payment_gateway_perf.rb` — load entrypoint  
- `perf/lib/mini_payment_gateway_perf/metrics.rb` — percentiles / summaries  
- `perf/lib/mini_payment_gateway_perf/report.rb` — JSON + Markdown  
- `perf/lib/mini_payment_gateway_perf/stubs.rb` — external I/O stubs  
- `perf/lib/mini_payment_gateway_perf/world.rb` — merchant fixture graph  
- `perf/lib/mini_payment_gateway_perf/harness.rb` — HTTP helpers (API, dashboard, Rack webhook)  
- `perf/lib/mini_payment_gateway_perf/scenarios.rb` — scenario registry  
- `perf/lib/mini_payment_gateway_perf/runner.rb` — orchestration  
- `lib/tasks/perf.rake` — Rake tasks  
- `spec/perf/perf_framework_spec.rb` — framework shape tests (no timing assertions)

## Framework tests

```bash
bundle exec rspec spec/perf/perf_framework_spec.rb
```

These validate registry wiring, report shape, metrics math, and deterministic stub behavior—not end-to-end SLA.
