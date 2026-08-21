import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["state", "query", "card", "empty"]

  filter() {
    const state = this.stateTarget.value
    const terms = this.queryTarget.value.toLowerCase().trim().split(/\s+/).filter(Boolean)
    let visible = 0

    this.cardTargets.forEach((card) => {
      const matchesState = !state || card.dataset.state === state
      const haystack = card.dataset.search || ""
      const matchesQuery = terms.every((term) => haystack.includes(term))
      card.hidden = !(matchesState && matchesQuery)
      if (!card.hidden) visible += 1
    })

    this.emptyTarget.hidden = visible > 0
  }
}
