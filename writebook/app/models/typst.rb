class Typst < ApplicationRecord
  include Leafable

  # Escaped so `Leaf::Searchable` does not strip Typst angle-bracket syntax
  # (labels, comparisons) as if it were HTML.
  def searchable_content
    ERB::Util.html_escape(source.to_s)
  end

  def markable
    source.to_s
  end

  def html_preview
    source.to_s
  end

  # Compiles this slide's Typst source to a self-contained SVG using the
  # Present2u slide theme. Raises TypstDocument::Error when the source is
  # invalid or typst is unavailable.
  def to_svg
    TypstDocument.slide(source.to_s).to_svg
  end

  # Compiles the source but degrades to an error block instead of raising, so
  # the show/edit views never 500 on a bad snippet.
  def rendered_svg
    to_svg
  rescue TypstDocument::Error => e
    %(<pre class="diagram-error" data-error="#{ERB::Util.html_escape(e.message)}">#{ERB::Util.html_escape(source.to_s)}</pre>)
  end

  # Content-addressed URL for the compiled SVG, so list/thumbnail views can use
  # an <img> without recompiling on every render. Nil when the source is invalid.
  def svg_url
    RenderedAsset.store(kind: :typst, source: source.to_s, options: { slide: true, theme: TypstDocument::SLIDE_THEME_VERSION })
  rescue StandardError
    nil
  end
end