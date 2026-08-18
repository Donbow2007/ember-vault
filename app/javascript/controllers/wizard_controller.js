import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["step", "indicator", "back", "next", "finish", "counter", "total", "bar", "summary"]

  connect() {
    this.position = 0
    this.render()
    this.update()
  }

  next() {
    if (this.position < this.stepTargets.length - 1) this.position += 1
    this.render()
  }

  back() {
    if (this.position > 0) this.position -= 1
    this.render()
  }

  go(event) {
    this.position = Number(event.currentTarget.dataset.step)
    this.render()
  }

  rememberRadio(event) {
    const input = event.currentTarget.matches("input[type=radio]") ? event.currentTarget : event.currentTarget.querySelector("input[type=radio]")
    if (input) input.dataset.wasChecked = input.checked ? "true" : "false"
  }

  toggleRadio(event) {
    const input = event.currentTarget
    if (input.dataset.wasChecked === "true") input.checked = false
    delete input.dataset.wasChecked
    this.update()
  }

  update() {
    const selected = [...this.element.querySelectorAll("input[data-size]:checked")]
    const megabytes = selected.reduce((total, input) => total + Number(input.dataset.size || 0), 0)
    this.totalTarget.textContent = this.formatSize(megabytes)
    this.barTarget.style.width = `${Math.min((megabytes / 150000) * 100, 100)}%`
    this.summaryTarget.textContent = selected.length === 0 ? "No content packages selected." : `${selected.length} package selections ready for review.`
  }

  render() {
    const final = this.position === this.stepTargets.length - 1
    this.stepTargets.forEach((step, index) => step.classList.toggle("active", index === this.position))
    this.indicatorTargets.forEach((item, index) => {
      item.classList.toggle("active", index === this.position)
      item.classList.toggle("complete", index < this.position)
    })
    this.backTarget.disabled = this.position === 0
    this.nextTarget.hidden = final
    this.finishTarget.hidden = !final
    this.counterTarget.textContent = `0${this.position + 1} / 0${this.stepTargets.length}`
    window.scrollTo({ top: 0, behavior: "smooth" })
  }

  formatSize(megabytes) {
    if (megabytes >= 1024) return `${(megabytes / 1024).toFixed(1)} GB`
    return `${megabytes.toLocaleString()} MB`
  }
}
