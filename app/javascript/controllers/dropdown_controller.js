import { Controller } from "@hotwired/stimulus"

/**
 * Accessible dropdown: toggles panel, closes on outside click and Escape,
 * keeps aria-expanded in sync.
 */
export default class extends Controller {
  static targets = ["menu", "trigger"]

  connect() {
    this.boundCloseOnClickOutside = this.closeOnClickOutside.bind(this)
    this.boundCloseOnEscape = this.closeOnEscape.bind(this)
  }

  disconnect() {
    this.close()
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    if (this.isOpen()) {
      this.close()
    } else {
      this.open()
    }
  }

  open() {
    if (!this.hasMenuTarget) return
    this.menuTarget.classList.remove("hidden")
    if (this.hasTriggerTarget) {
      this.triggerTarget.setAttribute("aria-expanded", "true")
    }
    document.addEventListener("click", this.boundCloseOnClickOutside, true)
    document.addEventListener("keydown", this.boundCloseOnEscape)
  }

  close() {
    if (!this.hasMenuTarget) return
    this.menuTarget.classList.add("hidden")
    if (this.hasTriggerTarget) {
      this.triggerTarget.setAttribute("aria-expanded", "false")
    }
    document.removeEventListener("click", this.boundCloseOnClickOutside, true)
    document.removeEventListener("keydown", this.boundCloseOnEscape)
  }

  closeOnClickOutside(event) {
    if (this.element.contains(event.target)) return
    this.close()
  }

  closeOnEscape(event) {
    if (event.key === "Escape") this.close()
  }

  isOpen() {
    return this.hasMenuTarget && !this.menuTarget.classList.contains("hidden")
  }
}
