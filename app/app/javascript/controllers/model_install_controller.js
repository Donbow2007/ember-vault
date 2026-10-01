import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.element.querySelectorAll(".model-install-button").forEach((button) => {
      button.addEventListener("click", () => this.install(button))
    })
  }

  async install(button) {
    const progress = button.parentElement.querySelector(".model-progress")
    const bar = progress.querySelector("i")
    const label = progress.querySelector("span")
    button.disabled = true
    button.textContent = "INSTALLING"
    progress.hidden = false

    try {
      const response = await fetch(button.dataset.installUrl)
      if (!response.ok || !response.body) throw new Error("Unable to start model install")

      const reader = response.body.getReader()
      const decoder = new TextDecoder()
      let buffer = ""

      while (true) {
        const { value, done } = await reader.read()
        if (done) break
        buffer += decoder.decode(value, { stream: true })
        const events = buffer.split("\n\n")
        buffer = events.pop()

        for (const event of events) {
          const line = event.split("\n").find((part) => part.startsWith("data: "))
          if (!line) continue
          const data = JSON.parse(line.slice(6))
          if (data.error) throw new Error(data.error)
          if (data.percent != null) {
            bar.style.width = `${data.percent}%`
            label.textContent = `${data.percent}%`
          } else if (data.downloaded) {
            label.textContent = `${(data.downloaded / 1048576).toFixed(1)} MB`
          }
          if (data.complete) window.location.reload()
        }
      }
    } catch (error) {
      button.disabled = false
      button.textContent = "RETRY"
      label.textContent = error.message
    }
  }
}
