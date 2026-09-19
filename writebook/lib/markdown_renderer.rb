require "rouge/plugins/redcarpet"

# Markdown renderer for technical slides. On top of Rouge-highlighted code it
# understands two extra fenced languages:
#
#   ```d2          D2 diagram, rendered with the TALA layout engine
#   ```d2-sketch   D2 diagram in the hand-drawn sketch style
#   ```latex       arbitrary LaTeX, compiled to a tightly cropped SVG
#
# Inline math ($...$, $$...$$) is rendered in the browser with KaTeX.
class MarkdownRenderer < Redcarpet::Render::HTML
  include Rouge::Plugins::Redcarpet

  DIAGRAM_LANGUAGES = {
    "d2" => { kind: :d2, options: { layout: "tala", theme: 301, transparent: true } },
    "tala" => { kind: :d2, options: { layout: "tala", theme: 301, transparent: true } },
    "d2-sketch" => { kind: :d2, options: { layout: "tala", sketch: true, theme: 301, transparent: true } },
    "d2sketch" => { kind: :d2, options: { layout: "tala", sketch: true, theme: 301, transparent: true } }
  }.freeze

  LATEX_LANGUAGES = %w[latex tex math equation].freeze

  TYPST_LANGUAGES = %w[typst typ].freeze

  def self.build
    renderer = MarkdownRenderer.new(ActionText::Markdown::DEFAULT_RENDERER_OPTIONS)
    Redcarpet::Markdown.new(renderer, ActionText::Markdown::DEFAULT_MARKDOWN_EXTENSIONS)
  end

  def initialize(*args)
    super
    @id_counts = Hash.new(0)
  end

  def header(text, header_level)
    unique_id(text).then do |id|
      "<h#{header_level} id='#{id}'>#{text} <a href='##{id}' class='heading__link' aria-hidden='true'>#</a></h#{header_level}>"
    end
  end

  def image(url, title, alt_text)
    %(<a title="#{title}" data-action="lightbox#open:prevent" data-lightbox-target="image" data-lightbox-url-value="#{url}?disposition=attachment" href="#{url}"><img src="#{url}" alt="#{alt_text}"></a>)
  end

  def block_code(code, language)
    key = language.to_s.downcase.strip

    if (diagram = DIAGRAM_LANGUAGES[key])
      rendered_asset_tag("diagram diagram--d2", diagram[:kind], code, diagram[:options], "D2 diagram")
    elsif LATEX_LANGUAGES.include?(key)
      rendered_asset_tag("diagram diagram--latex", :latex, code, {}, "LaTeX equation")
    elsif TYPST_LANGUAGES.include?(key)
      rendered_asset_tag("diagram diagram--typst", :typst, code, {}, "Typst document")
    else
      super
    end
  end

  private
    def rendered_asset_tag(classes, kind, source, options, alt)
      url = RenderedAsset.store(kind: kind, source: source, options: options)
      %(<div class="#{classes}"><img src="#{url}" alt="#{alt}" loading="lazy"></div>)
    rescue StandardError => e
      %(<pre class="diagram-error" data-error="#{ERB::Util.html_escape(e.message)}"><code>#{ERB::Util.html_escape(source)}</code></pre>)
    end

    def unique_id(text)
      text.parameterize.then do |base_id|
        @id_counts[base_id] += 1
        @id_counts[base_id] > 1 ? "#{base_id}-#{@id_counts[base_id]}" : base_id
      end
    end
end
