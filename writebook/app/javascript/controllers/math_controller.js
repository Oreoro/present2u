import { Controller } from "@hotwired/stimulus"
import renderMathInElement from "katex-auto-render"

// Renders LaTeX math in slide content with KaTeX. Supports $...$, $$...$$,
// \(...\) and \[...\]. Delimiters left unrendered (e.g. a lone currency $)
// are ignored rather than raising.
export default class extends Controller {
  connect() {
    renderMathInElement(this.element, {
      delimiters: [
        { left: "$$", right: "$$", display: true },
        { left: "\\[", right: "\\]", display: true },
        { left: "$", right: "$", display: false },
        { left: "\\(", right: "\\)", display: false }
      ],
      throwOnError: false,
      ignoredClasses: [ "diagram-error" ]
    })
  }
}