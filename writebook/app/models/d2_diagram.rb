require "open3"
require "tmpdir"
require "timeout"

# Renders D2 diagram source to SVG using the `d2` CLI.
#
# Defaults to the TALA layout engine and can render in D2's hand-drawn
# "sketch" style. The binary can be overridden with D2_BIN.
class D2Diagram
  class Error < StandardError; end

  RENDER_TIMEOUT = 25
  DEFAULT_LAYOUT = "tala".freeze
  # D2's "Terminal Grayscale" theme — a pure black/white base we recolor to the
  # Notion palette so every diagram matches the rest of the product.
  DEFAULT_THEME = 301
  # Theme 301 inks (recolored in #recolor).
  GRAYSCALE_INK = "#000410"
  GRAYSCALE_FILL = "#FFFFFF"

  def initialize(source, layout: DEFAULT_LAYOUT, sketch: false, theme: DEFAULT_THEME, dark_theme: nil, pad: 20, transparent: true)
    @source = source.to_s
    @layout = layout
    @sketch = sketch
    @theme = theme
    @dark_theme = dark_theme
    @pad = pad
    @transparent = transparent
  end

  def to_svg
    raise Error, "Empty diagram" if @source.strip.empty?

    Dir.mktmpdir("present2u-d2") do |dir|
      input = File.join(dir, "diagram.d2")
      output = File.join(dir, "diagram.svg")
      File.write(input, @source)

      _stdout, stderr, status = run(command(input, output))

      unless status.success? && File.exist?(output)
        raise Error, stderr.to_s.strip.presence || "d2 failed to render the diagram"
      end

      svg = File.read(output)
      svg = transparent_background(svg) if @transparent
      recolor(svg)
    end
  end

  private
    # Map the grayscale theme onto the Notion palette: ink strokes/text and a
    # soft warm-grey node fill. Other themes are left untouched.
    def recolor(svg)
      return svg unless @theme == DEFAULT_THEME

      svg
        .gsub(GRAYSCALE_INK, "#37352f")
        .gsub(GRAYSCALE_FILL, "#f7f7f5")
        .gsub('fill="white"', 'fill="#f7f7f5"')
    end

    def command(input, output)
      args = [ binary, "--layout=#{@layout}", "--theme=#{@theme}", "--pad=#{@pad}" ]
      args << "--sketch" if @sketch
      args << "--dark-theme=#{@dark_theme}" if @dark_theme
      args + [ input, output ]
    end

    def binary
      ENV.fetch("D2_BIN", "d2")
    end

    # D2 paints an opaque background rect as the first element of the SVG. On a
    # themed slide that reads as a white box behind the diagram, so make just
    # that rect transparent and let the slide show through.
    def transparent_background(svg)
      svg.sub(/<rect\b[^>]*stroke-width="0"[^>]*>/) do |rect|
        rect.sub(/fill="[^"]*"/, 'fill="transparent"')
      end
    end

    def run(args)
      Timeout.timeout(RENDER_TIMEOUT) { Open3.capture3(*args) }
    rescue Timeout::Error
      raise Error, "D2 rendering timed out"
    rescue Errno::ENOENT
      raise Error, "The d2 binary was not found (install D2 or set D2_BIN)"
    end
end
