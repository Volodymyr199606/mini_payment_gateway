# AI/RAG System Audit

Audit date: 2026-03-04. No refactors applied; report only.

---

## 1. Component Map (file paths)

| Component | File path(s) |
|-----------|--------------|
| **Ai::Rag::DocsIndex** | `app/services/ai/rag/docs_index.rb` |
| **Ai::Rag::DocsRetriever** | `app/services/ai/rag/docs_retriever.rb` |
| **Ai::Rag::RetrievalService** | `app/services/ai/rag/retrieval_service.rb` |
| **ContextGraph (RAG)** | `app/services/ai/rag/context_graph.rb` |
| **ContextGraph (Builder + Graph)** | `app/services/ai/context_graph/builder.rb`, `app/services/ai/context_graph/graph.rb` |
| **Ai::GraphExpandedRetriever** | `app/services/ai/graph_expanded_retriever.rb` |
| **BaseAgent** | `app/services/ai/agents/base_agent.rb` |
| **Agents** | `app/services/ai/agents/support_faq_agent.rb`, `operational_agent.rb`, `security_agent.rb`, `onboarding_agent.rb`, `reconciliation_agent.rb`, `reporting_calculation_agent.rb` |
| **AiChatSession / AiChatMessage** | `app/models/ai_chat_session.rb`, `app/models/ai_chat_message.rb` |
| **ConversationSummarizer** | `app/services/ai/conversation_summarizer.rb` |
| **ConversationContextBuilder** | `app/services/ai/conversation_context_builder.rb` |
| **Citation enforcement + empty retrieval** | `app/services/ai/agents/base_agent.rb` (inline) |

---

## 2. Per-component summary

### 2.1 Ai::Rag::DocsIndex

- **Public API:** `DocsIndex.instance`, `DocsIndex.reset!`, `#initialize`, `#build`, `#sections`, `#search(query, top_k: 5, allowed_files: nil, preferred_files: nil)` → array of section hashes.
- **Used by:** `DocsRetriever` (via `DocsIndex.instance`), `GraphExpandedRetriever` (default keyword retriever).
- **Tests:** `spec/services/ai/rag/docs_index_spec.rb` — search (short query, matching terms, top_k), sections shape. **Missing:** `instance`/`reset!` lifecycle, `allowed_files`/`preferred_files`, empty docs dir, Windows path normalization.
- **Duplication / naming:** None. Single source for keyword search.

---

### 2.2 Ai::Rag::DocsRetriever

- **Public API:** `#initialize(message, agent_key: nil)`, `#call` → `{ context_text:, citations: }`.
- **Used by:** `RetrievalService.call` when `AI_CONTEXT_GRAPH_ENABLED` is false; `spec/requests/ai_chat_spec.rb` stubs `DocsRetriever.new` (not `RetrievalService`).
- **Tests:** `spec/services/ai/rag/docs_retriever_spec.rb` — shape, authorize/capture content, max 6 sections, related sections, deterministic order. **Missing:** empty index fallback path, agent_key / AgentDocPolicy behavior, `allowed_files` yielding no hits.
- **Duplication:** `slugify`, `section_id`, citation building and context chunk formatting duplicated with `GraphExpandedRetriever` and `Ai::Rag::ContextGraph` (see below).

---

### 2.3 Ai::Rag::RetrievalService

- **Public API:** `RetrievalService.call(message, agent_key: nil)` → `{ context_text:, citations: }`; `RetrievalService.context_graph_enabled?` (class).
- **Used by:** `app/controllers/api/v1/ai/chat_controller.rb`, `app/controllers/dashboard/ai_controller.rb`.
- **Tests:** `spec/services/ai/rag/retrieval_service_spec.rb` — ENV flag, logging (Docs vs Graph path), smoke both paths. **Missing:** behavior when `GraphExpandedRetriever` returns empty (nil context); no request/spec that stubs `RetrievalService` instead of `DocsRetriever`.
- **Inconsistency:** When context graph is enabled, `agent_key` is not passed to `GraphExpandedRetriever` (no agent-scoped filtering/preference for graph path).

---

### 2.4 ContextGraph (RAG) — Ai::Rag::ContextGraph

- **Public API:** `ContextGraph.instance`, `ContextGraph.reset!`, `#initialize(docs_path: nil)`, `#build`, `#expand(seed_section_ids, max_hops: 1, max_nodes: 6)` → array of node ids, `#node(id)`, `#nodes`, `#section_id(file, anchor)` (used internally; same pattern as elsewhere).
- **Used by:** `DocsRetriever`, `GraphExpandedRetriever` (default graph).
- **Tests:** `spec/services/ai/rag/context_graph_spec.rb` — build (nodes, parent/child, prev/next, links), expand (deterministic, includes parent/prev/next/links, max_nodes, empty seeds), section_id format. **Missing:** `resolve_link` edge cases (path without docs/ prefix, missing file), `instance`/`reset!` with mtime.
- **Duplication:** Node shape and build logic (parent/child, prev/next, link resolution) largely duplicated in `Ai::ContextGraph::Builder`; `slugify`/`section_id` repeated in DocsRetriever, GraphExpandedRetriever, ContextGraph.

---

### 2.5 ContextGraph (Builder + Graph) — Ai::ContextGraph

- **Public API:** `Ai::ContextGraph::Builder.build(sections)` → `Graph`; `Graph#initialize(nodes)`, `#nodes`, `#neighbors(node_id)` → `[{ node_id:, edge_type: }]`, `#get(node_id)`.
- **Used by:** Only `spec/services/ai/context_graph_spec.rb`. **Not used** by DocsRetriever or GraphExpandedRetriever (they use `Ai::Rag::ContextGraph`).
- **Tests:** `spec/services/ai/context_graph_spec.rb` — Graph#get, #neighbors (parent, child, prev/next, links_to), Builder build. **Missing:** Integration with any retriever; consistency with Rag::ContextGraph node ids when built from same docs.
- **Inconsistency:** Two graph abstractions: `Ai::Rag::ContextGraph` (expand + node/nodes) vs `Ai::ContextGraph::Graph` (neighbors + get). Naming: `Rag::ContextGraph` vs `ContextGraph::Graph`; `#node(id)` vs `#get(node_id)`.

---

### 2.6 Ai::GraphExpandedRetriever

- **Public API:** `#initialize(query, keyword_retriever: nil, graph: nil)`, `#call` → `{ context_text:, citations:, seed_count:, expanded_count:, final_count: }`.
- **Used by:** `RetrievalService.call` when `AI_CONTEXT_GRAPH_ENABLED` is true.
- **Tests:** `spec/services/ai/graph_expanded_retriever_spec.rb` — call shape, expansion (seed + parent + next + optional links), max FINAL_TOP_K, context cap, dedup, expansion cap per seed (many children), empty seeds. **Missing:** Retriever/graph injection when keyword returns hits but graph has no node for a section id; scoring tie-breaking; behavior when graph returns nodes without `:content`.
- **Duplication:** `slugify`, `section_id`, `normalize_file`, `build_citation`, context chunk building (same pattern as DocsRetriever and ContextGraph).

---

### 2.7 BaseAgent + all agents

- **BaseAgent public API:** `#initialize(merchant_context: nil, message:, context_text:, citations: [], conversation_history: [], memory_text: '')`, `#call` → `{ reply:, citations:, model_used:, fallback_used: }`, `#detect_low_context?(context_text)`, `#agent_name`. Protected: `#system_instructions`, `#build_messages`, `#groq_client`, etc.
- **Subclasses:** SupportFaqAgent, OperationalAgent, SecurityAgent, OnboardingAgent, ReconciliationAgent override `system_instructions` only; ReportingCalculationAgent overrides `call` (no RAG, no citation enforcement).
- **Used by:** API and dashboard chat controllers (via `agent_class_for` + `build_agent`); Router picks agent key.
- **Tests:** `spec/services/ai/agents/base_agent_spec.rb` — reply format (filler strip, inline citation strip), citations array, low context fallback, empty retrieval guardrail, citation enforcement (re-ask once / no re-ask), strip_inline_citations. `operational_agent_spec.rb`, `reporting_calculation_agent_spec.rb` exist. **Missing:** Dedicated specs for SupportFaqAgent, SecurityAgent, OnboardingAgent, ReconciliationAgent (only exercised via base or request specs); retry path when second LLM call returns blank; citation check with non-ASCII file/heading.
- **Duplication:** None across agents; agent_class_for duplicated in both chat controllers (same case/when list).

---

### 2.8 AiChatSession / AiChatMessage + summarizer + context builder

- **Models:** `AiChatSession` (belongs_to :merchant, has_many :ai_chat_messages); `AiChatMessage` (role, content, optional merchant/session). Scopes: `recent_first`, `chronological`.
- **ConversationSummarizer:** `ConversationSummarizer.call(ai_chat_session)` → summary string; uses NEW_MESSAGES_THRESHOLD, MIN_MESSAGES_FOR_FIRST_SUMMARY; persists summary_text/summary_updated_at; sanitizes via MessageSanitizer.
- **ConversationContextBuilder:** `ConversationContextBuilder.call(ai_chat_session, max_turns: 8)` → `{ summary_text:, recent_messages:, memory_text: }`; `#to_groq_messages`, `#format_for_memory(exclude_last: false)`.
- **Used by:** Dashboard `AiController` only (session/messages, ConversationContextBuilder for memory/history, then agent; ConversationSummarizer called from ConversationStore or elsewhere — see ConversationStore).
- **Tests:** `spec/services/ai/conversation_context_builder_spec.rb` (call, summary_text, recent_messages order/truncation, format_for_memory, to_groq_messages); `spec/services/ai/conversation_summarizer_spec.rb` (thresholds, persist, sanitization). **Missing:** AiChatSession/AiChatMessage model specs; integration of summarizer with context builder (who triggers summarizer and when).
- **Naming:** `summary_text` vs `memory_text` (builder returns both; controller uses `memory_text` from builder).

---

### 2.9 Citation enforcement + empty retrieval fallback

- **Location:** `app/services/ai/agents/base_agent.rb`.
- **Empty retrieval:** `detect_low_context?(context_text)` (blank or length < LOW_CONTEXT_THRESHOLD); returns `low_context_fallback_message` (EMPTY_RETRIEVAL_FALLBACK + WHERE_TO_LOOK_SUGGESTIONS), no LLM call.
- **Citation enforcement:** After first LLM reply, if `@citations.any?` and `!reply_references_citations?(content, @citations)` (reply must contain file path or basename of a citation), append assistant + user "Answer again and cite sources." and call Groq once more; use second reply if present.
- **Used by:** All agents that use BaseAgent#call (all except ReportingCalculationAgent).
- **Tests:** base_agent_spec: empty retrieval guardrail, citation enforcement (re-ask + second call args, no re-ask when reply cites). **Missing:** Retry when second reply is blank or error; `reply_references_citations?` with nil/empty citations; WHERE_TO_LOOK_SUGGESTIONS hardcoded list (no test that list matches existing docs).

---

## 3. Duplicated logic and inconsistent naming

| Issue | Locations |
|-------|-----------|
| **slugify** | `DocsRetriever`, `GraphExpandedRetriever`, `Rag::ContextGraph`, `ContextGraph::Builder` (same logic). |
| **section_id(file, anchor)** | `DocsRetriever`, `GraphExpandedRetriever`, `Rag::ContextGraph` (same `"#{file}##{anchor}"`). |
| **normalize_file (backslash)** | `DocsRetriever` (inline gsub), `GraphExpandedRetriever` (method). |
| **build_citation / build_citation_from_node** | `DocsRetriever` (two methods: from node vs from section), `GraphExpandedRetriever` (build_citation(node)); same keys :file, :heading, :anchor, :excerpt. |
| **Context chunk format** | Same header + truncation + MAX_CONTEXT_CHARS logic in DocsRetriever and GraphExpandedRetriever. |
| **Graph node shape** | Same in Rag::ContextGraph and ContextGraph::Builder (id, file, heading, anchor, level, content, parent_id, children_ids, prev_id, next_id, outgoing_link_ids). |
| **Naming** | `#node(id)` (Rag::ContextGraph) vs `#get(node_id)` (ContextGraph::Graph). Two modules: `Ai::Rag::ContextGraph` vs `Ai::ContextGraph` (Builder/Graph). |
| **agent_class_for** | Exact same case/when in `api/v1/ai/chat_controller.rb` and `dashboard/ai_controller.rb`. |

---

## 4. Prioritized TODO checklist (10–15 items)

1. **Stub RetrievalService in request specs**  
   `spec/requests/ai_chat_spec.rb` stubs `DocsRetriever`; entry point is `RetrievalService`. Stub `RetrievalService.call` (or both paths) so behavior is correct for either ENV and tests don’t depend on internal retriever.

2. **Pass agent_key into GraphExpandedRetriever when flag on**  
   When `AI_CONTEXT_GRAPH_ENABLED=true`, `RetrievalService` does not pass `agent_key` to `GraphExpandedRetriever`, so agent-specific allowed/preferred docs are not applied. Add optional `agent_key` (or allowed/preferred files) to GraphExpandedRetriever and use AgentDocPolicy there.

3. **Extract shared RAG helpers**  
   Add a shared module or small class for `slugify`, `section_id`, `normalize_file`, and citation building (and optionally context chunk formatting) used by DocsRetriever, GraphExpandedRetriever, and Rag::ContextGraph to remove duplication and keep behavior consistent.

4. **Unify or document the two graph implementations**  
   Either use `Ai::ContextGraph::Builder` + `Graph` in the RAG pipeline (with a single ContextGraph entry point) or clearly document that `Ai::ContextGraph` is for standalone/tests and `Ai::Rag::ContextGraph` is for production; align `#node` vs `#get` naming if both stay.

5. **DocsIndex: add tests for instance/reset! and filters**  
   Cover `instance`/`reset!` (and mtime in dev), `search(..., allowed_files: ..., preferred_files: ...)`, and empty docs directory.

6. **DocsRetriever: add tests for empty index and agent_key**  
   When index returns no sections; when agent_key yields AgentDocPolicy that restricts to files with no matches; assert citation shape when fallback to initial_hits is used.

7. **GraphExpandedRetriever: add edge-case tests**  
   Keyword returns section ids that are not in graph; graph node missing `:content`; scoring tie-breaking; optional agent_key/preferred files once supported.

8. **Rag::ContextGraph: add tests for resolve_link and instance**  
   Link resolution for paths without `docs/`, missing target file; `instance`/`reset!` with mtime in development.

9. **BaseAgent: add tests for citation retry edge cases**  
   Second LLM call returns blank or error; `reply_references_citations?` with nil/empty citations; optional: non-ASCII in file/heading.

10. **Add agent_class_for to a single place**  
    Extract the agent key → class map to a shared constant or `Ai::Router` (or a small `AgentRegistry`) and use it from both API and dashboard chat controllers to avoid drift.

11. **Specs for SupportFaq, Security, Onboarding, Reconciliation agents**  
    At least one example per agent (e.g. system_instructions or a single call with stubbed Groq) so overrides are exercised.

12. **AiChatSession / AiChatMessage model specs**  
    Validations, associations, scopes (chronological, recent_first).

13. **Document or test WHERE_TO_LOOK_SUGGESTIONS**  
    Ensure the list matches existing docs (or add a test that suggested paths exist in docs/) so the empty-retrieval message stays accurate.

14. **RetrievalService: handle empty graph result**  
    When `GraphExpandedRetriever` returns empty context (e.g. no docs), `result.slice(:context_text, :citations)` is fine, but log or test that downstream agent receives empty context and returns low_context fallback.

15. **ConversationSummarizer trigger**  
    Clarify where/when summarizer is called (e.g. from ConversationStore or after each message); add a short integration test or comment so the flow is obvious.

---

*End of audit.*
