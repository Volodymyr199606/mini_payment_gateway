import { Controller } from "@hotwired/stimulus"

/**
 * Clipboard copy: copies source text to clipboard, shows checkmark on success, "Copy failed" on error.
 * Targets: source (input/textarea/code with key), button (copy button with copy+check SVGs).
 */
export default class extends Controller {
  static targets = ["source", "button", "feedback"]
  static REVERT_MS = 1200
  static FAILURE_MS = 1500

  copy(event) {
    event.preventDefault()
    event.stopPropagation()

    const text = this.getText()
    if (!text) {
      this.showFailure()
      return
    }

    if (navigator.clipboard?.writeText) {
      navigator.clipboard.writeText(text)
        .then(() => this.showSuccess())
        .catch(() => this.fallbackCopy(text))
    } else {
      this.fallbackCopy(text)
    }
  }

  getText() {
    if (!this.hasSourceTarget) return ""
    const el = this.sourceTarget
    if (el.value != null) return String(el.value).trim()
    return el.textContent?.trim() ?? ""
  }

  showSuccess() {
    this.cancelTimers()
    if (this.hasButtonTarget) {
      this.buttonTarget.classList.add("is-copied")
      this.buttonTarget.setAttribute("aria-label", "Copied")
    }
    this.revertTimer = setTimeout(() => this.revert(), this.constructor.REVERT_MS)
  }

  showFailure() {
    this.cancelTimers()
    if (this.hasFeedbackTarget) {
      const el = this.feedbackTarget
      el.textContent = "Copy failed"
      el.classList.remove("clipboard-feedback-hidden")
      el.classList.add("clipboard-feedback-error")
      this.failureTimer = setTimeout(() => {
        el.textContent = ""
        el.classList.add("clipboard-feedback-hidden")
        el.classList.remove("clipboard-feedback-error")
      }, this.constructor.FAILURE_MS)
    }
  }

  revert() {
    this.cancelTimers()
    if (this.hasButtonTarget) {
      this.buttonTarget.classList.remove("is-copied")
      this.buttonTarget.setAttribute("aria-label", "Copy API key")
    }
  }

  fallbackCopy(text) {
    const textarea = document.createElement("textarea")
    textarea.value = text
    textarea.setAttribute("readonly", "")
    textarea.style.position = "absolute"
    textarea.style.left = "-9999px"
    document.body.appendChild(textarea)
    textarea.select()
    try {
      const ok = document.execCommand("copy")
      if (ok) this.showSuccess()
      else this.showFailure()
    } catch {
      this.showFailure()
    } finally {
      document.body.removeChild(textarea)
    }
  }

  cancelTimers() {
    if (this.revertTimer) clearTimeout(this.revertTimer)
    this.revertTimer = null
    if (this.failureTimer) clearTimeout(this.failureTimer)
    this.failureTimer = null
  }

  disconnect() {
    this.cancelTimers()
  }
}
