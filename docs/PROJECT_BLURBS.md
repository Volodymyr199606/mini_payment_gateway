# Project blurbs (resume / portfolio)

Use these as starting points; **tune for your voice** and the job description.

---

## One line

> **Mini Payment Gateway** — Rails 7.2 monolith modeling a multi-tenant payment platform (lifecycle, ledger, idempotency, webhooks) with an integrated AI assistant (tools, RAG, policy, audit/replay).

---

## 2–3 lines (resume)

> Built a **Rails 7.2 payment gateway** with merchant-scoped REST API and dashboard: **authorize–capture–void–refund** lifecycle, **double-entry-style ledger**, **idempotent** mutations, and **webhook** verification/delivery. Integrated an **AI assistant** using deterministic tools and RAG over internal docs, with **merchant isolation**, **policy checks**, and **audit/replay** tooling. **Default processor is simulated**; **Stripe test mode** supported via adapter pattern.

---

## LinkedIn / portfolio (short paragraph)

> I designed and implemented **Mini Payment Gateway**, a **Rails 7.2** service-oriented monolith that demonstrates how a real payment product could be structured: **multi-tenant** APIs, **ledger-backed** financial state, **idempotency** for safe retries, **webhook** verification and outbound delivery, and **audit logging**. The project also includes an **AI layer** grounded in the same domain—**deterministic tools**, **RAG** over documentation, **policy enforcement**, and **observability** (analytics, health, replay). The stack emphasizes **correctness** (invariant tests), **security** (threat model, rate limiting), and **CI quality gates**—not a toy CRUD app.

---

## Interview intro (30–45 seconds)

> “I have a project called Mini Payment Gateway. It’s a Rails monolith that implements a **Braintree-style** flow: merchants integrate via API, we model **payment intents** and **transactions**, and we only write to the **ledger** when money actually moves—on capture and refund. **Idempotency** is built in, and **webhooks** are verified per provider adapter. I also built an **AI assistant** on top of the same data: **merchant-scoped tools** for structured queries, **RAG** from internal docs for explanations, and **policy** so the model can’t cross tenant boundaries. **Tests** include payment invariants, AI contracts, and adversarial scenarios. **Processor is simulated by default**; I can plug in **Stripe sandbox** for a realistic integration path.”

---

## “Tell me about a project you’re proud of”

> “I’m proud of **Mini Payment Gateway** because it forced me to think like **platform** engineering, not just features. I had to get **payment state** and **ledger semantics** right—**authorize** doesn’t create a charge ledger entry; **capture** does. I implemented **idempotency** so retries don’t double-charge, and **webhooks** with signature verification and **deduplication** where possible.  
>  
> On top of that, I integrated **AI** in a defensible way: **tools** that call the same services as the API, **RAG** from versioned docs, and a **policy layer** so we don’t leak data across merchants.  
>  
> I invested in **tests**—invariant specs for money, **contract tests** for AI payloads, **adversarial** tests for cross-tenant access—and **documentation** (C4, sequences, threat model). It’s a **portfolio** codebase, but **production-like** in how correctness and operability are treated.”

---

## Keywords for ATS (optional)

`Ruby on Rails` · `PostgreSQL` · `REST API` · `multi-tenant` · `idempotency` · `ledger` · `webhooks` · `service objects` · `adapter pattern` · `RAG` · `LLM tooling` · `CI` · `RSpec`
