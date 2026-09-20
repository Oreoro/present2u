import { Controller } from "@hotwired/stimulus"

const PRESENTING_KEY = "present2u:presenting"

// Presentation mode: fullscreen 16:9 slide stage with keyboard, click and
// swipe navigation, a slide counter, progress bar, speaker notes and an
// overview grid. The controller lives on <body> so its actions work from any
// page; the active slide publishes its state through a .slide-stage element.
export default class extends Controller {
  static targets = [ "stage", "counter", "progress", "notes", "overview" ]

  connect() {
    this.boundKeydown = this.#onKeydown.bind(this)
    document.addEventListener("keydown", this.boundKeydown)

    if (this.#presenting) this.#enter()
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKeydown)
  }

  // Arm present mode then let the link navigate to the first slide. Fullscreen
  // must be requested here, during the click gesture, so the browser allows it.
  arm() {
    sessionStorage.setItem(PRESENTING_KEY, "1")
    this.#requestFullscreen()
  }

  // Enter present mode immediately (used from a slide where we can fullscreen).
  start(event) {
    event?.preventDefault()
    sessionStorage.setItem(PRESENTING_KEY, "1")
    this.#enter()
    this.#requestFullscreen()
  }

  stop(event) {
    event?.preventDefault()
    sessionStorage.removeItem(PRESENTING_KEY)
    this.element.classList.remove("presenting")
    this.#closeNotes()
    this.#closeOverview()
    if (document.fullscreenElement) document.exitFullscreen?.()
  }

  toggle(event) {
    event?.preventDefault()
    this.#presenting ? this.stop() : this.start(event)
  }

  next(event) {
    event?.preventDefault()
    this.#go(this.#stage?.dataset.nextUrl)
  }

  previous(event) {
    event?.preventDefault()
    this.#go(this.#stage?.dataset.prevUrl)
  }

  overviewToggle(event) {
    event?.preventDefault()
    if (!this.hasOverviewTarget) return
    this.overviewTarget.hidden = !this.overviewTarget.hidden
    this.#syncAria()
  }

  notesToggle(event) {
    event?.preventDefault()
    if (!this.hasNotesTarget) return
    this.notesTarget.hidden = !this.notesTarget.hidden
    this.#syncAria()
  }

  fullscreenToggle(event) {
    event?.preventDefault()
    if (document.fullscreenElement) {
      document.exitFullscreen?.()
    } else {
      this.#requestFullscreen()
    }
  }

  stageClick(event) {
    if (!this.#presenting) return
    if (event.target.closest("a, button, input, textarea, select, [data-present-ignore]")) return
    if (!this.overviewTarget.hidden || !this.notesTarget.hidden) return

    const next = event.clientX / window.innerWidth > 0.5
    this.#go(next ? this.#stage?.dataset.nextUrl : this.#stage?.dataset.prevUrl)
  }

  get #stage() {
    return this.hasStageTarget ? this.stageTarget : null
  }

  get #presenting() {
    return this.element.classList.contains("presenting") || sessionStorage.getItem(PRESENTING_KEY) === "1"
  }

  #enter() {
    this.element.classList.add("presenting")
    this.#updateHud()
  }

  #requestFullscreen() {
    if (!document.fullscreenElement && document.documentElement.requestFullscreen) {
      document.documentElement.requestFullscreen().catch(() => {})
    }
  }

  #go(url) {
    if (!url) return

    if (window.Turbo) {
      window.Turbo.visit(url)
    } else {
      window.location.href = url
    }
  }

  #updateHud() {
    const stage = this.#stage
    if (!stage) return

    if (this.hasCounterTarget) {
      this.counterTarget.textContent = `${stage.dataset.index} / ${stage.dataset.total}`
    }

    if (this.hasProgressTarget) {
      const total = Number(stage.dataset.total) || 1
      const index = Number(stage.dataset.index) || 1
      this.progressTarget.style.setProperty("--progress", `${(index / total) * 100}%`)
    }
  }

  #onKeydown(event) {
    if (event.target.closest("input, textarea, select")) return

    switch (event.key) {
      case " ":
        event.preventDefault()
        event.shiftKey ? this.#go(this.#stage?.dataset.prevUrl) : this.#go(this.#stage?.dataset.nextUrl)
        break
      case "PageDown":
      case "Enter":
        event.preventDefault()
        this.#go(this.#stage?.dataset.nextUrl)
        break
      case "PageUp":
        event.preventDefault()
        this.#go(this.#stage?.dataset.prevUrl)
        break
      case "Home":
        this.#go(this.#stage?.dataset.firstUrl)
        break
      case "End":
        this.#go(this.#stage?.dataset.lastUrl)
        break
      case "Escape":
        if (this.hasOverviewTarget && !this.overviewTarget.hidden) this.#closeOverview()
        else if (this.hasNotesTarget && !this.notesTarget.hidden) this.#closeNotes()
        else this.stop()
        break
      case "o":
      case "O":
        this.overviewToggle()
        break
      case "n":
      case "N":
        this.notesToggle()
        break
      case "f":
      case "F":
        this.fullscreenToggle()
        break
    }
  }

  #closeNotes() {
    if (this.hasNotesTarget) this.notesTarget.hidden = true
    this.#syncAria()
  }

  #closeOverview() {
    if (this.hasOverviewTarget) this.overviewTarget.hidden = true
    this.#syncAria()
  }

  #syncAria() {
    this.element.classList.toggle("notes-open", this.hasNotesTarget && !this.notesTarget.hidden)
    this.element.classList.toggle("overview-open", this.hasOverviewTarget && !this.overviewTarget.hidden)
  }
}