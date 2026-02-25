import { Controller } from "@hotwired/stimulus"

/**
 * ChatGPT-style clipboard copy: copies text to clipboard, swaps copy icon to checkmark on success,
 * or shows "Copy failed" on failure. Reverts after ~1.2s.
 */
export default class extends Controller {
  static values = { key: String }
  static targets = ["button", "source", "feedback"]
  static REVERT_MS = 1200
  static FAILURE_MS = 1500

  copy(event) {
    if (!this.hasButtonTarget || !this.buttonTarget.contains(event.target)) return
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
    const fromValue = this.keyValue?.trim()
    if (fromValue) return fromValue
    if (this.hasSourceTarget) {
      const el = this.sourceTarget
      return el.value != null ? el.value.trim() : el.textContent.trim()
    }
    return ""
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
      el.classList.add("clipboard-feedback-error")
      el.classList.remove("clipboard-feedback-hidden")
      this.failureTimer = setTimeout(() => {
        el.textContent = ""
        el.classList.remove("clipboard-feedback-error")
        el.classList.add("clipboard-feedback-hidden")
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
