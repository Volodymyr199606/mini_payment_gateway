import { Controller } from "@hotwired/stimulus"

/**
 * Dashboard AI Chat: fetches /dashboard/ai/chat, appends reply to transcript.
 * On Send: spinner while in-flight, checkmark pop on success, red x + shake on error.
 * Targets: transcript, input, sendButton, statusIcon.
 * Values: url (POST endpoint).
 */
export default class extends Controller {
  static targets = ["transcript", "input", "sendButton", "statusIcon", "error"]
  static values = { chatUrl: String }

  SUCCESS_MS = 700
  ERROR_MS = 700

  connect() {
    console.log("[AI_CHAT] connected")
    this.initialTranscript = this.transcriptTarget?.innerHTML
  }

  async send(event) {
    event.preventDefault()
    if (!this.hasInputTarget || !this.hasTranscriptTarget) return

    const message = this.inputTarget.value.trim()
    if (!message) {
      this.showErrorInUITarget("Please enter a message.")
      return
    }

    this.hideErrorInUITarget()
    this.appendUserBubble(message)
    this.scrollTranscriptToBottom()
    this.inputTarget.value = ""
    this.setStateSending()

    const url = this.chatUrlValue || "/dashboard/ai/chat"
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    try {
      const res = await fetch(url, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": csrfToken || ""
        },
        body: JSON.stringify({ message, agent: "auto" })
      })

      const data = await res.json().catch(() => ({}))
      if (!res.ok) {
        this.showErrorAnimation()
        this.showErrorInUITarget(data.message || data.error || `Request failed (${res.status})`)
        setTimeout(() => this.setIdle(), this.ERROR_MS)
        return
      }

      this.appendAssistantBubble(data.reply, data.agent, data.model_used, data.citations || [])
      this.scrollTranscriptToBottom()
      this.showSuccessAnimation()
      setTimeout(() => this.setIdle(), this.SUCCESS_MS)
    } catch (err) {
      this.showErrorAnimation()
      this.showErrorInUITarget(err.message || "Network error")
      setTimeout(() => this.setIdle(), this.ERROR_MS)
    }
  }

  appendUserBubble(text) {
    const transcript = this.transcriptTarget
    if (transcript.querySelector(".text-muted")) transcript.innerHTML = ""
    const wrap = document.createElement("div")
    wrap.className = "ai-bubble-row ai-bubble-row-user"
    const bubble = document.createElement("div")
    bubble.className = "ai-bubble ai-bubble-user"
    bubble.textContent = text
    wrap.appendChild(bubble)
    transcript.appendChild(wrap)
  }

  appendAssistantBubble(reply, agent, modelUsed, citations) {
    const transcript = this.transcriptTarget
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
    meta.textContent = `agent: ${agent || "agent"} · model: ${modelUsed || "—"}`
    assistantBubble.appendChild(meta)

    const actions = document.createElement("div")
    actions.className = "ai-bubble-actions"
    const copyBtn = document.createElement("button")
    copyBtn.type = "button"
    copyBtn.className = "ai-copy-btn"
    copyBtn.textContent = "Copy"
    copyBtn.setAttribute("aria-label", "Copy reply to clipboard")
    copyBtn.addEventListener("click", () => this.copyReply(reply || "", copyBtn))
    actions.appendChild(copyBtn)
    assistantBubble.appendChild(actions)

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

    assistantWrap.appendChild(assistantBubble)
    transcript.appendChild(assistantWrap)
  }

  scrollTranscriptToBottom() {
    const transcript = this.transcriptTarget
    const scrollContainer = transcript.closest(".ai-chat-transcript") || transcript
    if (scrollContainer) scrollContainer.scrollTop = scrollContainer.scrollHeight
  }

  showErrorInUITarget(message) {
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = message
      this.errorTarget.hidden = false
    }
  }

  hideErrorInUITarget() {
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = ""
      this.errorTarget.hidden = true
    }
  }

  setStateSending() {
    this.sendButtonTarget.disabled = true
    this.showSpinner()
  }

  setIdle() {
    this.sendButtonTarget.disabled = false
    this.hideStatusIcon()
  }

  showSpinner() {
    if (!this.hasStatusIconTarget) return
    this.statusIconTarget.className = "ai-status-icon"
    this.statusIconTarget.innerHTML = '<span class="ai-spinner"></span>'
  }

  showSuccessAnimation() {
    if (!this.hasStatusIconTarget) return
    this.statusIconTarget.className = "ai-status-icon ai-check ai-pop"
    this.statusIconTarget.innerHTML = `
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
        <path d="M5 12l5 5L19 7"/>
      </svg>
    `
  }

  showErrorAnimation() {
    if (!this.hasStatusIconTarget) return
    this.statusIconTarget.className = "ai-status-icon ai-x ai-shake"
    this.statusIconTarget.innerHTML = `
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
        <path d="M18 6L6 18M6 6l12 12"/>
      </svg>
    `
  }

  showErrorState() {
    if (!this.hasStatusIconTarget) return
    this.statusIconTarget.className = "ai-status-icon ai-x ai-shake"
    this.statusIconTarget.innerHTML = `
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
        <path d="M18 6L6 18M6 6l12 12"/>
      </svg>
    `
    setTimeout(() => this.hideStatusIcon(), this.ERROR_MS)
  }

  hideStatusIcon() {
    if (!this.hasStatusIconTarget) return
    this.statusIconTarget.className = "ai-status-icon ai-hidden"
    this.statusIconTarget.innerHTML = ""
  }

  async copyReply(text, buttonEl) {
    if (!text) return
    try {
      if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(text)
      } else {
        const ta = document.createElement("textarea")
        ta.value = text
        ta.setAttribute("readonly", "")
        ta.style.position = "absolute"
        ta.style.left = "-9999px"
        document.body.appendChild(ta)
        ta.select()
        document.execCommand("copy")
        document.body.removeChild(ta)
      }
      this.showCopyToast(buttonEl)
    } catch {
      // Silently fail
    }
  }

  showCopyToast(buttonEl) {
    const original = buttonEl.textContent
    buttonEl.textContent = "Copied ✓"
    buttonEl.classList.add("ai-copy-copied")
    setTimeout(() => {
      buttonEl.textContent = original
      buttonEl.classList.remove("ai-copy-copied")
    }, 1000)
  }
}
