require "open3"
require "tmpdir"
require "timeout"

# Compiles a Typst snippet or document to SVG using the `typst` CLI.
#
# Typst is a first-class render engine next to D2 and LaTeX. Two modes:
#
#   TypstDocument.new(source)         a raw figure — the author controls everything
#   TypstDocument.slide(source)       a 16:9 slide — the Present2u theme is applied
#
# The slide theme sets the page size, typography, heading/​code/link styling and a
# `p2u-title` helper, so a slide body is just content, not boilerplate.
class TypstDocument
  class Error < StandardError; end

  RENDER_TIMEOUT = 30

  # Typst paints the page with an opaque white rect as the first path. Drop it so
  # the diagram sits on the slide, then re-point the theme ink (and pure black)
  # at currentColor so text adapts to light and dark themes.
  BLACK = /fill="#(?:0{6}|1b1b1f|37352f)"/i

  # Bump when SLIDE_PREAMBLE changes so cached thumbnails are recompiled.
  SLIDE_THEME_VERSION = "2"

  SLIDE_PREAMBLE = <<~TYPST.freeze
    // Present2u slide theme — Notion-flavored
    #set page(width: 16cm, height: 9cm, margin: (x: 1.2cm, y: 1cm), fill: none)
    #set text(font: ("Helvetica Neue", "New Computer Modern"), size: 17pt, fill: rgb("#37352f"))
    #set par(leading: 0.62em, justify: false)
    #set list(indent: 1em, spacing: 0.5em, marker: [•])
    #set block(spacing: 0.9em)
    #show heading.where(level: 1): it => block(width: 100%, above: 0pt, below: 0.65em, text(size: 26pt, weight: "semibold", tracking: -0.2pt, it.body))
    #show heading.where(level: 2): it => block(above: 0.8em, below: 0.35em, text(size: 20pt, weight: "semibold", it.body))
    #show heading.where(level: 3): it => block(above: 0.6em, below: 0.3em, text(size: 17pt, weight: "semibold", it.body))
    #show raw: set text(font: ("JetBrains Mono", "DejaVu Sans Mono"), size: 0.86em)
    #show raw.where(block: true): it => block(width: 100%, fill: rgb("#f7f7f5"), stroke: 0.5pt + rgb("#e9e9e7"), inset: 10pt, radius: 4pt, it)
    #show link: set text(fill: rgb("#2383e2"))
    #let p2u-title(title, subtitle: none) = align(center + horizon)[
      #text(size: 32pt, weight: "semibold", tracking: -0.4pt, title)
      #if subtitle != none [
        #v(0.35em)
        #text(size: 18pt, fill: rgb("#787774"), subtitle)
      ]
    ]

    // Shrink a slide's content just enough to fit the page, so a long slide
    // scales down instead of spilling onto a second page.
    #let p2u-fit(body) = layout(size => {
      let content = block(width: size.width, body)
      let measured = measure(content)
      let factor = calc.min(1.0, size.height / calc.max(measured.height, 1pt))
      scale(x: factor * 100%, y: factor * 100%, origin: top + left, content)
    })
  TYPST

  def initialize(source, preamble: nil, root: nil, allow_multiple: false)
    @source = source.to_s
    @preamble = preamble
    @root = root
    @allow_multiple = allow_multiple
  end

  # A 16:9 slide with the Present2u theme applied.
  def self.slide(source, **options)
    new(source, preamble: SLIDE_PREAMBLE, **options)
  end

  def to_svg
    raise Error, "Empty Typst document" if document.strip.empty?

    Dir.mktmpdir("present2u-typst") do |dir|
      input = File.join(dir, "document.typ")
      File.write(input, document)

      _stdout, stderr, status = Timeout.timeout(RENDER_TIMEOUT) { Open3.capture3(*command(input, dir)) }
      pages = rendered_pages(dir)

      unless status.success? && pages.any?
        raise Error, stderr.to_s.strip.presence || "typst failed to render the document"
      end

      if pages.size > 1 && !@allow_multiple
        raise Error, "Typst content overflows the slide (#{pages.size} pages). Trim it or use a smaller text size."
      end

      recolor(File.read(pages.first))
    end
  rescue Timeout::Error
    raise Error, "Typst rendering timed out"
  rescue Errno::ENOENT
    raise Error, "The typst binary was not found (install Typst or set TYPST_BIN)"
  end

  private
    def document
      return @source if @preamble.nil?

      # Slide bodies are wrapped in the auto-fit helper so they always fit one page.
      [ @preamble, "#p2u-fit[\n#{@source}\n]" ].join("\n")
    end

    def command(input, dir)
      args = [ binary, "compile", "--format", "svg" ]
      args += [ "--root", @root ] if @root.present?
      args + [ input, File.join(dir, "document-{p}.svg") ]
    end

    def rendered_pages(dir)
      Dir[File.join(dir, "document-*.svg")].sort_by { |file| file[/-(\d+)\.svg\z/, 1].to_i }
    end

    def binary
      ENV.fetch("TYPST_BIN", "typst")
    end

    def recolor(svg)
      svg = svg.sub(/<path\b[^>]*?fill="#ffffff"[^>]*?>/) do |path|
        path.sub(/fill="#ffffff"/, 'fill="transparent"')
      end

      svg.gsub(BLACK, 'fill="currentColor"')
    end
end
