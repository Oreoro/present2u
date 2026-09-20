class TypstsController < LeafablesController
  # Compiles a Typst snippet to SVG for the live editor preview.
  def preview
    svg = TypstDocument.new(params[:source].to_s).to_svg
    render html: svg.html_safe
  rescue StandardError => e
    render plain: e.message, status: :unprocessable_entity
  end

  private
    def default_leaf_params
      { title: "Typst slide" }
    end

    def new_leafable
      Typst.new leafable_params
    end

    def leafable_params
      params.fetch(:typst, {}).permit(:source).with_defaults(source: default_source)
    end

    def default_source
      <<~TYPST
        // The slide theme is applied for you — just write content.
        // For a title slide use:  #p2u-title("My deck", subtitle: "A subtitle")

        = Your title

        Write *Typst* here. Inline math works: $E = m c^2$.

        - A bullet
        - Another bullet
      TYPST
    end
end
