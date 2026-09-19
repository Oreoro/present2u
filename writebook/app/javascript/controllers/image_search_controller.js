import { Controller } from "@hotwired/stimulus"

// Image picker backed by Context.dev. Looks up images referenced by a page
// (or a screenshot of it) and stores the chosen URL in the form so the server
// can download and attach it.
export default class extends Controller {
  static targets = [ "query", "kind", "results", "status", "url", "preview" ]
  static values = { searchUrl: String }

  async search(event) {
    event?.preventDefault()

    const source = this.queryTarget.value.trim()
    if (!source) return

    this.#status("Searching…")
    this.resultsTarget.replaceChildren()

    try {
      const params = new URLSearchParams({ source_url: source, kind: this.kindTarget.value })
      const response = await fetch(`${this.searchUrlValue}?${params}`, { headers: { Accept: "application/json" } })
      const payload = await response.json()

      if (!response.ok) throw new Error(payload.error || "Search failed")
      this.#render(payload.results || [])
    } catch (error) {
      this.#status(error.message, true)
    }
  }

  choose(button) {
    this.urlTarget.value = button.dataset.url
    if (this.hasPreviewTarget) this.previewTarget.src = button.dataset.url

    this.resultsTarget.querySelectorAll("button").forEach(candidate => {
      candidate.classList.toggle("is-selected", candidate === button)
    })

    this.#status("Selected — save the slide to attach it.")
  }

  #render(results) {
    if (results.length === 0) return this.#status("No images found on that page.", true)

    const items = results.map(result => {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "web-image-picker__result"
      button.dataset.url = result.src
      button.title = result.alt || result.src
      button.addEventListener("click", () => this.choose(button))

      const image = document.createElement("img")
      image.src = result.src
      image.alt = result.alt || ""
      image.loading = "lazy"

      button.append(image)
      return button
    })

    this.resultsTarget.replaceChildren(...items)
    this.#status(`${results.length} result(s). Click one to select it.`)
  }

  #status(message, isError = false) {
    this.statusTarget.textContent = message
    this.statusTarget.hidden = false
    this.statusTarget.classList.toggle("is-error", isError)
  }
}