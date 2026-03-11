import { Controller } from "@hotwired/stimulus"

/**
 * Dev AI Playground: POSTs to run endpoint, renders collapsible debug sections.
 */
export default class extends Controller {
  static targets = ["message", "merchantId", "submitBtn", "results", "loading", "error", "sections"]
  static values = { runUrl: String }

  run(event) {
    event.preventDefault()
    const message = this.messageTarget?.value?.trim()
    const merchantId = this.merchantIdTarget?.value
    const url = this.runUrlValue || "/dev/ai_playground/run"

    if (!message) {
      this.showError("Please enter a message.")
      return
    }

    this.hideError()
    this.resultsTarget.hidden = false
    this.loadingTarget.hidden = false
    this.sectionsTarget.innerHTML = ""
    this.submitBtnTarget.disabled = true

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    fetch(url, {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": csrfToken || ""
      },
      body: JSON.stringify({ message, merchant_id: merchantId || null })
    })
      .then(r => r.json().then(d => ({ ok: r.ok, status: r.status, data: d })).catch(() => ({ ok: r.ok, data: {} })))
      .then(({ ok, data }) => {
        this.loadingTarget.hidden = true
        this.submitBtnTarget.disabled = false

        if (!ok) {
          this.showError(data.error || data.message || "Request failed")
          return
        }

        if (data.error) {
          this.showError(data.error)
          return
        }

        this.renderSections(data)
      })
      .catch(err => {
        this.loadingTarget.hidden = true
        this.submitBtnTarget.disabled = false
        this.showError(err.message || "Network error")
      })
  }

  usePreset(event) {
    const preset = event.currentTarget.dataset.preset
    if (preset && this.hasMessageTarget) {
      this.messageTarget.value = preset
    }
  }

  showError(msg) {
    this.errorTarget.textContent = msg
    this.errorTarget.hidden = false
  }

  hideError() {
    this.errorTarget.textContent = ""
    this.errorTarget.hidden = true
  }

  renderSections(data) {
    const sections = [
      { key: "input", title: "Input" },
      { key: "parsing", title: "Parsing" },
      { key: "routing", title: "Routing" },
      { key: "retrieval", title: "Retrieval" },
      { key: "tools", title: "Tools" },
      { key: "orchestration", title: "Orchestration" },
      { key: "memory", title: "Memory" },
      { key: "composition", title: "Composition" },
      { key: "response", title: "Final Response" },
      { key: "debug", title: "Debug" },
      { key: "audit", title: "Audit" }
    ]

    const extra = { request_id: data.request_id, latency_ms: data.latency_ms }
    if (extra.request_id || extra.latency_ms) {
      const meta = this.buildSection("Meta", { ...extra })
      this.sectionsTarget.appendChild(meta)
    }

    for (const { key, title } of sections) {
      const val = data[key]
      if (val == null || (typeof val === "object" && Object.keys(val).length === 0)) continue

      const el = this.buildSection(title, val, key === "response")
      this.sectionsTarget.appendChild(el)
    }
  }

  buildSection(title, data, isResponse = false) {
    const details = document.createElement("details")
    details.className = "dev-playground-section"
    const summary = document.createElement("summary")
    summary.textContent = title
    details.appendChild(summary)

    const content = document.createElement("div")
    content.className = "section-content"

    if (isResponse && data.reply != null) {
      const replyEl = document.createElement("div")
      replyEl.className = "dev-playground-response-text"
      replyEl.textContent = data.reply
      content.appendChild(replyEl)
      if (data.citations && data.citations.length > 0) {
        const pre = document.createElement("pre")
        pre.textContent = "Citations: " + JSON.stringify(data.citations, null, 2)
        content.appendChild(pre)
      }
    } else if (typeof data === "object" && !Array.isArray(data)) {
      const pre = document.createElement("pre")
      pre.textContent = JSON.stringify(data, null, 2)
      content.appendChild(pre)
    } else {
      const pre = document.createElement("pre")
      pre.textContent = String(data)
      content.appendChild(pre)
    }

    details.appendChild(content)
    return details
  }
}
