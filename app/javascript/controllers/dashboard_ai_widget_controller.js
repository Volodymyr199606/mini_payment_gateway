import { Controller } from "@hotwired/stimulus"

/**
 * Dashboard AI Widget: floating chat button, panel with transcript.
 * Posts to /dashboard/ai/chat (session auth). Supports agent selector.
 * Targets: toggleButton, panel, transcript, input, sendButton, agentSelect, btnLabel, btnSpinner, btnCheck, btnError.
 * Values: chatUrl (POST endpoint).
 */
export default class extends Controller {
  static targets = ["toggleButton", "panel", "transcript", "input", "sendButton", "agentSelect", "btnLabel", "btnSpinner", "btnCheck", "btnError"]
  static values = { chatUrl: String }

  SUCCESS_MS = 700
  ERROR_MS = 700

  toggle() {
    const open = this.panelTarget.classList.toggle("open")
    this.panelTarget.setAttribute("aria-hidden", !open)
  }

  close() {
    this.panelTarget.classList.remove("open")
    this.panelTarget.setAttribute("aria-hidden", "true")
  }

  async send(event) {
    event.preventDefault()
    if (!this.hasInputTarget || !this.hasTranscriptTarget) return

    const message = this.inputTarget.value.trim()
    if (!message) {
      this.showErrorState()
      return
    }

    this.setStateSending()

    const url = this.chatUrlValue || "/dashboard/ai/chat"
    const agent = this.hasAgentSelectTarget ? this.agentSelectTarget.value : "auto"
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    try {
      const res = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": csrfToken || ""
        },
        body: JSON.stringify({ message, agent })
      })

      const data = await res.json().catch(() => ({}))
      if (!res.ok) {
        this.showErrorAnimation()
        setTimeout(() => this.setIdle(), this.ERROR_MS)
        return
      }

      this.appendToTranscript(message, data.reply, data.agent, data.model_used, data.citations || [], data.debug)
      this.inputTarget.value = ""
      this.inputTarget.focus()
      this.showSuccessAnimation()
      setTimeout(() => this.setIdle(), this.SUCCESS_MS)
    } catch (err) {
      this.showErrorAnimation()
      setTimeout(() => this.setIdle(), this.ERROR_MS)
    }
  }

  setStateSending() {
    this.sendButtonTarget.disabled = true
    if (this.hasBtnLabelTarget) this.btnLabelTarget.hidden = true
    if (this.hasBtnSpinnerTarget) this.btnSpinnerTarget.hidden = false
    if (this.hasBtnCheckTarget) this.btnCheckTarget.hidden = true
    if (this.hasBtnErrorTarget) this.btnErrorTarget.hidden = true
  }

  setIdle() {
    this.sendButtonTarget.disabled = false
    if (this.hasBtnLabelTarget) this.btnLabelTarget.hidden = false
    if (this.hasBtnSpinnerTarget) this.btnSpinnerTarget.hidden = true
    if (this.hasBtnCheckTarget) this.btnCheckTarget.hidden = true
    if (this.hasBtnErrorTarget) this.btnErrorTarget.hidden = true
  }

  showSuccessAnimation() {
    if (this.hasBtnLabelTarget) this.btnLabelTarget.hidden = true
    if (this.hasBtnSpinnerTarget) this.btnSpinnerTarget.hidden = true
    if (this.hasBtnCheckTarget) {
      this.btnCheckTarget.hidden = false
      this.btnCheckTarget.classList.add("ai-pop")
    }
    if (this.hasBtnErrorTarget) this.btnErrorTarget.hidden = true
  }

  showErrorAnimation() {
    if (this.hasBtnLabelTarget) this.btnLabelTarget.hidden = true
    if (this.hasBtnSpinnerTarget) this.btnSpinnerTarget.hidden = true
    if (this.hasBtnCheckTarget) this.btnCheckTarget.hidden = true
    if (this.hasBtnErrorTarget) {
      this.btnErrorTarget.hidden = false
      this.btnErrorTarget.classList.add("ai-shake")
    }
  }

  buildDebugPanel(debug) {
    const details = document.createElement("details")
    details.className = "ai-debug-panel"
    const summary = document.createElement("summary")
    summary.textContent = "Debug"
    summary.setAttribute("title", "AI_DEBUG mode")
    details.appendChild(summary)
    const content = document.createElement("div")
    content.className = "ai-debug-content"
    const fmt = (v) => (v == null || v === "") ? "—" : String(v)
    const bool = (v) => (v === true || v === "true") ? "yes" : "no"
    const sections = [
      { title: "Routing", rows: [
        ["agent", debug.selected_agent],
        ["retriever", debug.selected_retriever ?? debug.retriever],
        ["graph", bool(debug.graph_enabled)],
        ["vector", bool(debug.vector_enabled)]
      ]},
      { title: "Retrieval", rows: [
        ["sections", fmt(debug.retrieved_sections_count ?? debug.final_sections_count)],
        ["citations", fmt(debug.citations_count)],
        ["context_truncated", bool(debug.context_truncated)],
        ["context_chars", fmt(debug.final_context_chars) ? `${debug.final_context_chars} chars` : null]
      ].filter(r => r[1] != null)},
      { title: "Memory", rows: [
        ["memory_used", bool(debug.memory_used)],
        ["summary_used", bool(debug.summary_used)],
        ["recent_msgs", fmt(debug.recent_messages_count)],
        ["current_topic", fmt(debug.current_topic)],
        ["memory_truncated", bool(debug.memory_truncated)],
        ["memory_chars", fmt(debug.final_memory_chars) ? `${debug.final_memory_chars} chars` : null]
      ].filter(r => r[1] != null)},
      { title: "Guardrails", rows: [
        ["fallback_used", bool(debug.fallback_used)],
        ["citation_reask", bool(debug.citation_reask_used)]
      ]},
      { title: "Model / timing", rows: [
        ["model", fmt(debug.model_used)],
        ["latency", fmt(debug.latency_ms) != "—" ? `${debug.latency_ms} ms` : "—"]
      ]}
    ]
    for (const sec of sections) {
      const block = document.createElement("div")
      block.className = "ai-debug-section"
      const h = document.createElement("div")
      h.className = "ai-debug-section-title"
      h.textContent = sec.title
      block.appendChild(h)
      const grid = document.createElement("div")
      grid.className = "ai-debug-rows"
      for (const [label, val] of sec.rows) {
        if (val == null) continue
        const row = document.createElement("div")
        row.className = "ai-debug-row"
        row.innerHTML = `<span class="ai-debug-label">${label}</span><span class="ai-debug-val">${val}</span>`
        grid.appendChild(row)
      }
      block.appendChild(grid)
      content.appendChild(block)
    }
    details.appendChild(content)
    return details
  }

  showErrorState() {
    if (this.hasBtnErrorTarget) {
      this.btnErrorTarget.hidden = false
      this.btnErrorTarget.classList.add("ai-shake")
      setTimeout(() => {
        this.btnErrorTarget.hidden = true
        this.btnErrorTarget.classList.remove("ai-shake")
      }, this.ERROR_MS)
    }
  }

  appendToTranscript(userMsg, reply, agent, modelUsed, citations, debug) {
    const transcript = this.transcriptTarget

    const userWrap = document.createElement("div")
    userWrap.className = "ai-bubble-row ai-bubble-row-user"
    const userBubble = document.createElement("div")
    userBubble.className = "ai-bubble ai-bubble-user"
    userBubble.textContent = userMsg
    userWrap.appendChild(userBubble)
    transcript.appendChild(userWrap)

    const assistantWrap = document.createElement("div")
    assistantWrap.className = "ai-bubble-row ai-bubble-row-assistant"
    const assistantBubble = document.createElement("div")
    assistantBubble.className = "ai-bubble ai-bubble-assistant"

    const replyText = document.createElement("div")
    replyText.className = "ai-bubble-content"
    replyText.textContent = reply || "No reply."
    assistantBubble.appendChild(replyText)

    const meta = document.createElement("div")
    meta.className = "ai-bubble-meta"
    const agentName = agent || "agent"
    const modelLabel = modelUsed || "—"
    meta.textContent = `agent: ${agentName} · model: ${modelLabel}`
    assistantBubble.appendChild(meta)

    if (citations && citations.length > 0) {
      const details = document.createElement("details")
      details.className = "ai-sources"
      const summary = document.createElement("summary")
      summary.textContent = "Sources"
      details.appendChild(summary)
      const ul = document.createElement("ul")
      ul.className = "ai-sources-list"
      for (const c of citations) {
        const file = c.file || c["file"] || ""
        const heading = c.heading || c["heading"] || ""
        let excerpt = c.excerpt || c["excerpt"] || ""
        if (excerpt.length > 160) excerpt = excerpt.slice(0, 160) + "…"
        const li = document.createElement("li")
        li.textContent = `${file} :: ${heading}${excerpt ? ` — ${excerpt}` : ""}`
        ul.appendChild(li)
      }
      details.appendChild(ul)
      assistantBubble.appendChild(details)
    }

    if (debug && typeof debug === "object") {
      assistantBubble.appendChild(this.buildDebugPanel(debug))
    }

    assistantWrap.appendChild(assistantBubble)
    transcript.appendChild(assistantWrap)
    transcript.scrollTop = transcript.scrollHeight
  }
}
