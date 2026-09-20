require "open3"
require "tmpdir"

module P2u
  # Renders a manifest to distributable artifacts: a self-contained HTML deck,
  # speaker notes as Markdown, and a PDF (via headless Chrome when available).
  class Exporter
    class Error < StandardError; end

    # Layouts that already render their own title, so no separate kicker is drawn.
    TITLED_LAYOUTS = %w[
      title section content two-column compare code-split metric-row image image-grid
      references recap qa end
    ].freeze

    CHROME_PATHS = [
      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
      "/Applications/Chromium.app/Contents/MacOS/Chromium",
      "/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary"
    ].freeze

    def initialize(manifest)
      @manifest = manifest.is_a?(Manifest) ? manifest : Manifest.new(manifest)
    end

    def to_html
      Render::Document.new(deck: @manifest.deck, slides: slide_entries, title: deck_title).to_html
    end

    def to_notes
      lines = [ "# #{deck_title}", "" ]

      @manifest.slides.each_with_index do |slide, index|
        lines << "## #{index + 1}. #{slide_title(slide)}"
        lines << ""
        lines << (slide["notes"].to_s.presence || "_No speaker notes._")
        lines << ""
      end

      lines.join("\n")
    end

    def to_pdf(path)
      chrome = self.class.chrome_binary
      raise Error, "No Chrome or Chromium found — install one, or export HTML and print to PDF." unless chrome

      Dir.mktmpdir("p2u-export") do |dir|
        html_path = File.join(dir, "deck.html")
        File.write(html_path, to_html)
        output = File.expand_path(path)

        _stdout, stderr, status = Open3.capture3(
          chrome, "--headless=new", "--disable-gpu", "--no-pdf-header-footer",
          "--virtual-time-budget=5000", "--print-to-pdf=#{output}", "file://#{html_path}"
        )

        unless status.success? && File.exist?(output)
          raise Error, "PDF export failed: #{stderr.to_s.lines.last.to_s.strip.presence || 'unknown error'}"
        end
      end

      path
    end

    def filename(extension)
      "#{deck_title.parameterize.presence || 'deck'}.#{extension}"
    end

    def self.chrome_binary
      from_path = %w[google-chrome chromium chromium-browser google-chrome-stable].find do |name|
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, name)) }
      end
      return from_path if from_path

      CHROME_PATHS.find { |candidate| File.executable?(candidate) }
    end

    private
      def deck_title
        @manifest.deck["title"].presence || "Untitled deck"
      end

      def slide_title(slide)
        slide["title"].presence || "Untitled"
      end

      def slide_entries
        dark = deck_dark?
        format = deck_format
        @manifest.slides.map do |slide|
          layout = slide["layout"].to_s
          typst = (slide["format"].presence || format).to_s == "typst"
          {
            html: Render::Slide.new(slide, dark: dark, client_markdown: false, format: (typst ? "typst" : "markdown")).to_html,
            layout: layout,
            kicker: (typst || TITLED_LAYOUTS.include?(layout) ? nil : slide["title"].presence),
            notes: slide["notes"]
          }
        end
      end

      def deck_format
        format = @manifest.deck["format"].presence || @manifest.deck["engine"].presence || "markdown"
        format.to_s
      end

      def deck_theme
        theme = @manifest.deck["theme"]
        theme.is_a?(Hash) ? theme["preset"].to_s : theme.to_s
      end

      def deck_dark?
        deck_theme != "white"
      end
  end
end
