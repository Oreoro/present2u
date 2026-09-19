module P2u
  # The slide layout vocabulary of P2U/1. Each layout declares what it needs,
  # what content it accepts and which block kinds it allows. This registry is
  # the single source of truth used by the validator and published in the
  # JSON Schema.
  module Layouts
    DEFINITIONS = {
      "title"       => { summary: "Deck or talk title",        required: %w[title], content: :optional },
      "section"     => { summary: "Section divider",           required: %w[title], content: :optional },
      "content"     => { summary: "Markdown content",          content: :required },
      "two-column"  => { summary: "Two content columns",       slots: %w[left right], content: :optional },
      "compare"     => { summary: "Side-by-side comparison",   slots: %w[left right], content: :optional },
      "code-split"  => { summary: "Code beside prose",         slots: %w[code prose], content: :optional },
      "full-code"   => { summary: "Full-bleed code",           allowed_blocks: %w[code], require_block: true, content: :optional },
      "diagram"     => { summary: "Diagram focus",             allowed_blocks: %w[diagram], require_block: true, content: :optional },
      "equation"    => { summary: "Equation focus",            allowed_blocks: %w[equation], require_block: true, content: :optional },
      "table"       => { summary: "Data table",                allowed_blocks: %w[table markdown], content: :optional },
      "metric-row"  => { summary: "KPI cards",                 allowed_blocks: %w[metric], require_block: true, content: :optional },
      "timeline"    => { summary: "Timeline or roadmap",       content: :optional },
      "quote"       => { summary: "Pull quote",                content: :optional },
      "image"       => { summary: "Image slide",               allowed_blocks: %w[image], content: :optional },
      "image-grid"  => { summary: "Image gallery",             allowed_blocks: %w[image], require_block: true, content: :optional },
      "references"  => { summary: "Bibliography",              content: :optional },
      "recap"       => { summary: "Summary",                   content: :optional },
      "qa"          => { summary: "Questions",                 content: :optional },
      "end"         => { summary: "Closing slide",             content: :optional }
    }.freeze

    # Legacy DeckBuilder slide types map onto layouts.
    ALIASES = {
      "divider" => "section",
      "page" => "content",
      "picture" => "image",
      "typst" => "content",
      "" => "content"
    }.freeze

    class << self
      def resolve(name)
        key = name.to_s.strip.downcase
        ALIASES.fetch(key, key)
      end

      def key?(name) = DEFINITIONS.key?(resolve(name))
      def fetch(name) = DEFINITIONS.fetch(resolve(name))
      def keys = DEFINITIONS.keys
      def legacy?(name) = ALIASES.key?(name.to_s.strip.downcase)

      def default = "content"
    end
  end
end
