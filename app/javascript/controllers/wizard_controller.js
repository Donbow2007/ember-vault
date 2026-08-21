import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["step", "indicator", "back", "next", "finish", "counter", "total", "bar", "summary", "storageSelection", "storageSelectionBar", "storageProjectedFree", "storageSummary", "storageTrack", "termsAcceptance"]
  static values = { storageTotalMb: Number, storageUsedMb: Number, storageFreeMb: Number }

  connect() {
    this.position = 0
    this.render()
    this.update()
  }

  next() {
    if (!this.termsAcceptedForCurrentStep()) return
    if (this.position < this.stepTargets.length - 1) this.position += 1
    this.render()
  }

  back() {
    if (this.position > 0) this.position -= 1
    this.render()
  }

  go(event) {
    const destination = Number(event.currentTarget.dataset.step)
    if (destination > this.position && !this.termsAcceptedForCurrentStep()) return
    this.position = destination
    this.render()
  }

  termsChanged() {
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
      .filter((input) => Number(input.dataset.size || 0) > 0)
    const resources = new Map()
    selected.forEach((input) => {
      const ids = (input.dataset.packageIds || input.value).split(",")
      const sizes = (input.dataset.packageSizes || input.dataset.size || "0").split(",")
      ids.forEach((id, index) => resources.set(id, Number(sizes[index] || 0)))
    })
    const megabytes = [...resources.values()].reduce((total, size) => total + size, 0)
    const usedPercent = this.storageTotalMbValue > 0 ? (this.storageUsedMbValue / this.storageTotalMbValue) * 100 : 0
    const selectedPercent = this.storageTotalMbValue > 0 ? (megabytes / this.storageTotalMbValue) * 100 : 0
    const visibleSelectedPercent = Math.min(selectedPercent, Math.max(100 - usedPercent, 0))
    const projectedFree = Math.max(this.storageFreeMbValue - megabytes, 0)
    const exceedsStorage = megabytes > this.storageFreeMbValue

    this.totalTarget.textContent = this.formatSize(megabytes)
    this.barTarget.style.width = `${Math.min(selectedPercent, 100)}%`
    this.summaryTarget.textContent = resources.size === 0 ? "No content packages selected." : `${resources.size} unique packages ready for review.`
    this.storageSelectionTargets.forEach((target) => { target.textContent = this.formatSize(megabytes) })
    this.storageSelectionBarTargets.forEach((target) => { target.style.width = `${visibleSelectedPercent}%` })
    this.storageProjectedFreeTargets.forEach((target) => { target.textContent = this.formatSize(projectedFree) })
    this.storageTrackTargets.forEach((target) => {
      target.classList.toggle("over-capacity", exceedsStorage)
      target.setAttribute("aria-label", `${this.formatSize(this.storageUsedMbValue)} currently used, ${this.formatSize(megabytes)} selected, ${this.formatSize(projectedFree)} projected free`)
    })
    this.storageSummaryTargets.forEach((target) => { target.textContent = this.storageMessage(resources.size, megabytes, projectedFree, exceedsStorage) })
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
    this.nextTarget.disabled = !this.termsAcceptedForCurrentStep()
    this.counterTarget.textContent = `0${this.position + 1} / 0${this.stepTargets.length}`
    window.scrollTo({ top: 0, behavior: "smooth" })
  }

  termsAcceptedForCurrentStep() {
    const current = this.stepTargets[this.position]
    return !current?.dataset.termsStep || (this.hasTermsAcceptanceTarget && this.termsAcceptanceTarget.checked)
  }

  formatSize(megabytes) {
    if (megabytes >= 1024) return `${(megabytes / 1024).toFixed(1)} GB`
    return `${megabytes.toLocaleString()} MB`
  }

  storageMessage(selectionCount, megabytes, projectedFree, exceedsStorage) {
    if (selectionCount === 0) return "Choose library content or an optional model to preview its storage use."
    if (exceedsStorage) return `Selected media exceeds available storage by ${this.formatSize(megabytes - this.storageFreeMbValue)}.`

    return `${selectionCount} selections add ${this.formatSize(megabytes)} and leave about ${this.formatSize(projectedFree)} free.`
  }
}
