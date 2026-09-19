module Api
  # Self-describing entry point so an agent can discover the API.
  class DocsController < BaseController
    # GET /api
    def show
      render json: {
        name: "Present2u API",
        description: "Create and edit technical presentation decks (slides with LaTeX, D2 diagrams and code).",
        auth: "Authorization: Bearer <api_token>",
        manifest_format: {
          deck: {
            title: "Attention Is All You Need",
            subtitle: "optional",
            author: "optional",
            theme: "black | blue | green | magenta | orange | violet | white",
            slides: [
              { type: "section", title: "Attention", body: "The Transformer", theme: "dark" },
              { type: "content", title: "Scaled dot-product attention", body: "Markdown with $math$, ```latex, ```d2, ```d2-sketch and code fences.", notes: "Speaker notes", sketch: false },
              { type: "image", title: "Figure", image_url: "https://…", caption: "optional" }
            ]
          }
        },
        endpoints: {
          "GET /api/schema" => "P2U/1 manifest JSON Schema (the compiler contract)",
          "GET /api/toolchain" => "Report the compiler stack (markdown, d2, latex, versions)",
          "POST /api/compile" => "Parse + validate + plan a manifest without persisting (body: manifest JSON, or {source, format, render})",
          "POST /api/compose" => "Compose a manifest from a prompt and optional source notes ({prompt, sources, slides, theme, create})",
          "POST /api/export" => "Export a manifest to self-contained HTML or Markdown notes (body: manifest, or {source, format, to})",
          "GET /api/decks" => "List decks",
          "GET /api/decks/:id" => "Show a deck with its slides",
          "POST /api/decks" => "Create a deck from a manifest",
          "POST /api/decks/import" => "Bulk create a deck (same body)",
          "POST /api/decks/:id/plan" => "Diff a manifest against a deck (read-only)",
          "POST /api/decks/:id/apply" => "Idempotently apply a manifest to a deck",
          "PATCH /api/decks/:id" => "Update deck metadata",
          "DELETE /api/decks/:id" => "Delete a deck",
          "POST /api/decks/:deck_id/slides" => "Add a slide",
          "PATCH /api/decks/:deck_id/slides/:id" => "Update a slide",
          "DELETE /api/decks/:deck_id/slides/:id" => "Delete a slide",
          "GET /api/templates" => "List ready-made technical templates",
          "POST /api/templates/:key" => "Create a deck from a template"
        },
        slide_types: %w[section content image typst],
        formats: %w[markdown typst],
        layouts: P2u::Layouts.keys,
        blocks: P2u::Blocks.keys,
        diagram_languages: %w[d2 d2-sketch latex typst]
      }
    end
  end
end
