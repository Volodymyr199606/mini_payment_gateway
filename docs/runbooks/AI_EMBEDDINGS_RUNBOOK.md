# AI Embeddings Runbook

Hybrid retrieval uses pgvector and `doc_section_embeddings`. This runbook covers backfill, smoke test, and troubleshooting.

## Prerequisites

- **pgvector:** PostgreSQL extension must be installed before migrating.
  - [Installation](https://github.com/pgvector/pgvector#installation) (OS-specific).
  - Docker: use an image that includes pgvector (e.g. `pgvector/pgvector:pg16`) or install in your image.
- **Migration:** `rails db:migrate` creates the `doc_section_embeddings` table and enables the `vector` extension (if available).

## Environment variables

| Variable | Purpose |
|----------|---------|
| `EMBEDDING_API_KEY` | API key for embeddings (OpenAI or compatible). |
| `OPENAI_API_KEY` | Fallback if `EMBEDDING_API_KEY` not set. |
| `EMBEDDING_BASE_URL` | Optional; override API base URL. |
| `EMBEDDING_MODEL` | Optional; override model (e.g. `text-embedding-3-small`). |
| `AI_VECTOR_RAG_ENABLED` | Set to `true` to enable hybrid retrieval in the app. |
| `DRY_RUN` | Set to `1` when running backfill to use stub embeddings (no API call, no DB writes). |

## Running the backfill

1. Set an embedding API key:
   ```bash
   export EMBEDDING_API_KEY="your_key"
   # or
   export OPENAI_API_KEY="your_key"
   ```

2. Run the backfill:
   ```bash
   rake ai:backfill_doc_embeddings
   ```

3. **Success:** Logs show `event: ai_backfill_start`, then `event: ai_backfill_finish` with `sections_processed`, `upserts`, `failures`, `duration_ms`. Console prints `Done. Upserted N embeddings.`

4. **DRY run (no API, no writes):** Use stub vectors to validate the loop without calling the API or writing to the DB:
   ```bash
   DRY_RUN=1 rake ai:backfill_doc_embeddings
   ```

## Smoke task

Run the hybrid retrieval smoke test (checks pgvector, table, optional backfill, one retrieval):

```bash
rake ai:smoke_hybrid
```

- **Success:** Prints `pgvector: ok`, `doc_section_embeddings: ok`, then retriever name, sections returned count, and first 3 citations.
- If embedding keys are not set, the task runs backfill in DRY_RUN mode (no API, no DB writes), then runs one retrieval (keyword + any existing vector data).

## When to rerun backfill

- After adding or editing Markdown files under `docs/`.
- After changing section structure (e.g. heading levels) that affects `DocsIndex` / section ids.
- If hybrid retrieval returns stale or missing sections for updated docs.

## Troubleshooting

| Issue | Check |
|-------|--------|
| `doc_section_embeddings table not found` | Install pgvector, then run `rails db:migrate`. |
| `pgvector extension not enabled` | Install pgvector on the Postgres server; enable with migration `enable_extension 'vector'`. |
| `Set EMBEDDING_API_KEY or OPENAI_API_KEY` | Set one of these (or use `DRY_RUN=1` for a dry run). |
| Backfill skips sections (`embed_failed_or_wrong_dims`) | Check API key, base URL, and model; check logs for `ai_backfill_skip`. |
| Hybrid retrieval returns 0 vector hits | Run backfill so `doc_section_embeddings` is populated; ensure `AI_VECTOR_RAG_ENABLED=true`. |
| Retrieval logs missing `vector_hits_count` | That key is only present when the retriever is HybridRetriever. |
