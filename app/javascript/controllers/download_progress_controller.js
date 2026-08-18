import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String, interval: { type: Number, default: 2000 } }

  connect() {
    this.schedule()
  }

  disconnect() {
    this.cancel()
  }

  schedule() {
    this.cancel()
    if (this.element.dataset.active !== "true") return

    this.timer = window.setTimeout(() => this.refresh(), this.intervalValue)
  }

  async refresh() {
    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "text/html", "X-Requested-With": "XMLHttpRequest" },
        credentials: "same-origin"
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      this.element.innerHTML = await response.text()
      const marker = this.element.querySelector("[data-downloads-active]")
      this.element.dataset.active = marker?.dataset.downloadsActive || "false"
    } catch (error) {
      console.warn("Local download status refresh failed", error)
    } finally {
      this.schedule()
    }
  }

  cancel() {
    if (this.timer) window.clearTimeout(this.timer)
    this.timer = null
  }
}
