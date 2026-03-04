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
      const debugDetails = document.createElement("details")
      debugDetails.className = "ai-debug-panel"
      const debugSummary = document.createElement("summary")
      debugSummary.textContent = "Debug (AI_DEBUG)"
      debugDetails.appendChild(debugSummary)
      const pre = document.createElement("pre")
      pre.className = "ai-debug-content"
      const lines = [
        `retriever: ${debug.retriever ?? "—"}`,
        `seed_section_ids: ${JSON.stringify(debug.seed_section_ids ?? [])}`,
        `expanded_section_ids: ${JSON.stringify(debug.expanded_section_ids ?? [])}`,
        debug.expanded_with_edges ? `expanded_with_edges: ${JSON.stringify(debug.expanded_with_edges)}` : null,
        `final_included_section_ids: ${JSON.stringify(debug.final_included_section_ids ?? [])}`,
        `context_budget_used: ${debug.context_budget_used ?? "—"} / ${debug.max_context_chars ?? "—"}`,
        `context_truncated: ${!!debug.context_truncated}`,
        `summary_used: ${!!debug.summary_used}`
      ].filter(Boolean)
      pre.textContent = lines.join("\n")
      debugDetails.appendChild(pre)
      assistantBubble.appendChild(debugDetails)
    }

    assistantWrap.appendChild(assistantBubble)
    transcript.appendChild(assistantWrap)
    transcript.scrollTop = transcript.scrollHeight
  }
}
