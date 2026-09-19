module P2u
  # The content block vocabulary of P2U/1. Blocks are the typed units that make
  # up a slide body. They compile down to Markdown fences that the existing
  # MarkdownRenderer already understands (d2, d2-sketch, latex, code).
  module Blocks
    DEFINITIONS = {
      "markdown"   => { summary: "Inline Markdown",        required: %w[body] },
      "code"       => { summary: "Highlighted code",       required: %w[source], defaults: { "lang" => "text" } },
      "diagram"    => { summary: "Diagram (D2, Mermaid…)", required: %w[source], defaults: { "lang" => "d2" } },
      "equation"   => { summary: "LaTeX equation",         required: %w[source] },
      "table"      => { summary: "Data table" },
      "chart"      => { summary: "Chart from data" },
      "image"      => { summary: "Image",                  any: %w[url src image_url] },
      "video"      => { summary: "Video embed",            required: %w[url] },
      "metric"     => { summary: "Metric or KPI",          required: %w[value label] },
      "quote"      => { summary: "Pull quote",             required: %w[text] },
      "callout"    => { summary: "Callout",                required: %w[body] },
      "definition" => { summary: "Term definition",        required: %w[term body] },
      "references" => { summary: "Reference list",         required: %w[items] },
      "notes-only" => { summary: "Speaker-only content",   required: %w[body] },
      "spacer"     => { summary: "Vertical spacer" }
    }.freeze

    # Diagram engines the compiler knows how to route.
    ENGINES = %w[d2 d2-sketch tala typst mermaid graphviz tikz].freeze

    class << self
      def key?(name) = DEFINITIONS.key?(name.to_s.strip.downcase)
      def fetch(name) = DEFINITIONS.fetch(name.to_s.strip.downcase)
      def keys = DEFINITIONS.keys
    end
  end
end
