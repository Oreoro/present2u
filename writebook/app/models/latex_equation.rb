require "open3"
require "tmpdir"
require "timeout"

# Compiles a LaTeX math snippet to a tightly-cropped SVG.
#
# Display environments are normalised into math-mode boxes so the snippet can be
# measured with \sbox and the page sized to fit exactly. Shell escape is disabled
# and compilation is time-boxed.
class LatexEquation
  class Error < StandardError; end

  RENDER_TIMEOUT = 30
  PADDING_PT = 2.0

  PACKAGES = <<~TEX.freeze
    \\usepackage{amsmath,amssymb,amsfonts}
    \\usepackage{mathtools}
    \\usepackage{bm}
  TEX

  # Display environments that can't live inside a math-mode box.
  UNSUPPORTED = /\\(begin|end)\{(tikzpicture|pspicture|picture|figure|table)\}/

  ENVIRONMENT_REWRITES = [
    [ /\\begin\{align\*?\}/, "\\\\begin{aligned}" ],
    [ /\\end\{align\*?\}/, "\\\\end{aligned}" ],
    [ /\\begin\{gather\*?\}/, "\\\\begin{gathered}" ],
    [ /\\end\{gather\*?\}/, "\\\\end{gathered}" ],
    [ /\\begin\{multline\*?\}/, "\\\\begin{gathered}" ],
    [ /\\end\{multline\*?\}/, "\\\\end{gathered}" ],
    [ /\\begin\{equation\*?\}/, "" ],
    [ /\\end\{equation\*?\}/, "" ]
  ].freeze

  def initialize(source, display: true)
    @source = source.to_s
    @display = display
  end

  def to_svg
    raise Error, "Empty equation" if @source.strip.empty?
    raise Error, "TikZ/picture environments aren't supported yet — use a D2 diagram instead." if @source.match?(UNSUPPORTED)

    body = wrapped_body

    Dir.mktmpdir("present2u-tex") do |dir|
      dimensions = probe(dir, body)
      pdf = compile(dir, body, dimensions)
      use_current_color(convert_to_svg(dir, pdf))
    end
  end

  private
    def wrapped_body
      source = normalize(@source.strip)

      return source if source.start_with?("$", "\\(")
      if source.start_with?("\\[")
        return "$\\displaystyle #{source.sub(/\A\\\[/, '').sub(/\\\]\s*\z/, '')}$"
      end

      @display ? "$\\displaystyle #{source}$" : "$#{source}$"
    end

    def normalize(source)
      ENVIRONMENT_REWRITES.reduce(source) { |text, (pattern, replacement)| text.gsub(pattern, replacement) }
    end

    def probe(dir, body)
      tex = <<~TEX
        \\documentclass[12pt]{article}
        #{PACKAGES}
        \\newsavebox{\\presenttwobox}
        \\begin{document}
        \\sbox{\\presenttwobox}{#{body}}
        \\typeout{PRESENT2U-BOX: \\the\\wd\\presenttwobox|\\the\\ht\\presenttwobox|\\the\\dp\\presenttwobox}
        \\noindent\\usebox{\\presenttwobox}
        \\end{document}
      TEX

      compile_tex(dir, "probe", tex)

      log = File.read(File.join(dir, "probe.log"))
      match = log.match(/PRESENT2U-BOX: ([\d.]+)pt\|([\d.]+)pt\|([\d.]+)pt/)

      unless match
        message = log[/^!.*$/] || "Could not measure the LaTeX snippet"
        raise Error, message.strip
      end

      width, height, depth = match.captures.map(&:to_f)
      { width: width, height: height, depth: depth }
    end

    def compile(dir, body, dimensions)
      width = dimensions[:width] + (PADDING_PT * 2)
      height = dimensions[:height] + dimensions[:depth] + (PADDING_PT * 2)

      tex = <<~TEX
        \\documentclass[12pt]{article}
        \\usepackage[paperwidth=#{width}pt,paperheight=#{height}pt,margin=0pt]{geometry}
        #{PACKAGES}
        \\pagestyle{empty}
        \\newsavebox{\\presenttwobox}
        \\begin{document}
        \\sbox{\\presenttwobox}{#{body}}
        \\noindent\\usebox{\\presenttwobox}
        \\end{document}
      TEX

      compile_tex(dir, "equation", tex)
      File.join(dir, "equation.pdf")
    end

    def compile_tex(dir, name, tex)
      path = File.join(dir, "#{name}.tex")
      File.write(path, tex)

      args = [
        ENV.fetch("PDFLATEX_BIN", "pdflatex"),
        "-no-shell-escape",
        "-interaction=nonstopmode",
        "-halt-on-error",
        "-output-directory=#{dir}",
        path
      ]

      _stdout, stderr, status = Timeout.timeout(RENDER_TIMEOUT) { Open3.capture3(*args) }

      unless status.success?
        log = File.exist?(File.join(dir, "#{name}.log")) ? File.read(File.join(dir, "#{name}.log")) : ""
        message = log[/^!.*$/] || stderr.to_s.strip.presence || "pdflatex failed"
        raise Error, message.strip
      end
    rescue Timeout::Error
      raise Error, "LaTeX rendering timed out"
    rescue Errno::ENOENT
      raise Error, "pdflatex was not found (install a TeX distribution)"
    end

    # pdftocairo emits the equation in solid black. Re-point those paint servers
# at `currentColor` so the glyphs inherit the slide's ink colour and stay
# legible on dark themes instead of vanishing into the background.
    def use_current_color(svg)
      svg.gsub(/fill="rgb\(\s*0%,\s*0%,\s*0%\s*\)"/, 'fill="currentColor"')
         .gsub(/stroke="rgb\(\s*0%,\s*0%,\s*0%\s*\)"/, 'stroke="currentColor"')
    end

    def convert_to_svg(dir, pdf)
      output = File.join(dir, "equation.svg")
      args = [ ENV.fetch("PDFTOCAIRO_BIN", "pdftocairo"), "-svg", pdf, output ]

      _stdout, stderr, status = Timeout.timeout(RENDER_TIMEOUT) { Open3.capture3(*args) }

      unless status.success? && File.exist?(output)
        raise Error, stderr.to_s.strip.presence || "pdftocairo failed to convert the equation"
      end

      File.read(output)
    rescue Timeout::Error
      raise Error, "LaTeX conversion timed out"
    rescue Errno::ENOENT
      raise Error, "pdftocairo was not found (install poppler)"
    end
end
