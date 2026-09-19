import { Controller } from "@hotwired/stimulus"

// Live Typst preview: debounce edits in the source textarea, POST the source to
// the preview endpoint and swap in the compiled SVG.
export default class extends Controller {
  static targets = [ "source", "preview" ]
  static values = { url: String }

  connect() {
    this.#schedule()
  }

  render() {
    this.#schedule()
  }

  #schedule() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.#compile(), 400)
  }

  async #compile() {
    if (!this.hasSourceTarget || !this.hasPreviewTarget) return

    const body = new FormData()
    body.append("source", this.sourceTarget.value)

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: { "X-CSRF-Token": this.#csrfToken() },
        body
      })

      if (response.ok) this.previewTarget.innerHTML = await response.text()
    } catch (error) {
      // Keep the last good preview when the network hiccups.
    }
  }

  #csrfToken() {
    return document.querySelector("meta[name=csrf-token]")?.content || ""
  }
}