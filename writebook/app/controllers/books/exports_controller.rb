module Books
  # Exports a deck through the P2U compiler: a self-contained HTML deck, or
  # Markdown speaker notes. Mirrors `p2u export` / `POST /api/export`.
  class ExportsController < ApplicationController
    def show
      book = Book.accessable_or_published.find(params[:book_id])

      manifest = P2u::DeckManifest.from(
        book,
        url_for: ->(attachment) { rails_blob_url(attachment.blob, host: request.base_url) }
      )
      exporter = P2u::Exporter.new(P2u::Manifest.new(manifest))

      case params[:to].to_s
      when "notes", "md", "markdown"
        send_data exporter.to_notes,
          filename: exporter.filename("md"),
          type: "text/markdown; charset=utf-8",
          disposition: "attachment"
      else
        send_data exporter.to_html,
          filename: exporter.filename("html"),
          type: "text/html; charset=utf-8",
          disposition: "attachment"
      end
    end
  end
end
