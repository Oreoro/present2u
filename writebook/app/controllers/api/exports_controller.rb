module Api
  # Export a P2U/1 manifest to a distributable artifact. HTML is a single
  # self-contained file; notes is Markdown. PDF export runs through the CLI
  # (`p2u export --to pdf`) because it needs a headless browser.
  class ExportsController < BaseController
    # POST /api/export
    def create
      exporter = P2u::Exporter.new(P2u::Parser.parse(source, format: source_format))

      case export_format
      when "html"
        render json: { format: "html", filename: exporter.filename("html"), content: exporter.to_html }
      when "notes", "md", "markdown"
        render json: { format: "notes", filename: exporter.filename("md"), content: exporter.to_notes }
      else
        render json: { error: "Unsupported export format #{export_format.inspect}. Use html or notes." },
          status: :unprocessable_entity
      end
    end

    private
      def source
        params[:source].presence || request.raw_post.presence || "{}"
      end

      def source_format
        explicit = params[:source_format].presence || params[:format].presence
        return explicit.to_s if explicit.present?
        return "json" unless params[:source].present?

        nil
      end

      def export_format
        (params[:to].presence || "html").to_s
      end
  end
end
