import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }

  connect() {
    this.timeout = window.setTimeout(() => this.refresh(), 1000)
  }

  disconnect() {
    window.clearTimeout(this.timeout)
    this.abortController?.abort()
  }

  async refresh() {
    this.abortController = new AbortController()

    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "text/html" },
        cache: "no-store",
        signal: this.abortController.signal
      })
      if (!response.ok) throw new Error(`Assistant status ${response.status}`)

      this.element.outerHTML = await response.text()
    } catch (error) {
      if (error.name !== "AbortError") {
        this.timeout = window.setTimeout(() => this.refresh(), 2500)
      }
    }
  }
}
