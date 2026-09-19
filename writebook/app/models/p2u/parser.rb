require "yaml"

module P2u
  # Turns a manifest source string into a P2u::Manifest. Supports three surfaces
  # that compile to the same AST:
  #
  #   JSON      — machine / tool-call friendly
  #   YAML      — canonical, human and agent friendly
  #   Markdown  — front matter for deck meta, `---` between slides
  class Parser
    MARKDOWN_SEPARATOR = /\n[ \t]*---[ \t]*\n/
    FORMATS = %w[json yaml yml markdown md].freeze

    def self.parse(source, format: nil)
      new(source, format: format).parse
    end

    def initialize(source, format: nil)
      @source = source.is_a?(String) ? source : source.to_json
      @format = format&.to_s&.strip&.downcase.presence
    end

    def parse
      raise ParseError, "Manifest source is empty" if @source.strip.empty?

      format = @format || detect_format
      case format
      when "json" then parse_json
      when "yaml", "yml" then parse_yaml
      when "markdown", "md" then parse_markdown
      else raise ParseError, "Unsupported format: #{format.inspect} (expected one of #{FORMATS.join(', ')})"
      end
    rescue ParseError
      raise
    rescue StandardError => e
      raise ParseError, "Could not parse #{format} manifest: #{e.message}"
    end

    private
      def detect_format
        stripped = @source.lstrip
        return "json" if stripped.start_with?("{", "[")
        return "markdown" if markdown_front_matter?(stripped)
        return "markdown" if @source.match?(MARKDOWN_SEPARATOR) && !yaml_like?(stripped)

        "yaml"
      end

      # A Markdown document has front matter delimited by a second `---`; a
      # plain YAML document only has the leading document marker.
      def markdown_front_matter?(text)
        text.start_with?("---") && text.match?(/\A---[ \t]*\r?\n.*?\r?\n---[ \t]*(\r?\n|\z)/m)
      end

      def yaml_like?(text)
        text.match?(/\A(p2u|version|deck|slides)\s*:/)
      end

      def parse_json
        Manifest.new(JSON.parse(@source))
      end

      def parse_yaml
        Manifest.new(YAML.safe_load(@source, permitted_classes: [ Date, Time ], aliases: true) || {})
      end

      def parse_markdown
        text = @source.dup
        meta = {}

        if text.start_with?("---")
          rest = text.sub(/\A---\s*\n/, "")
          if rest =~ /\n---\s*\n/
            front, body = rest.split(/\n---\s*\n/, 2)
            parsed = YAML.safe_load(front, permitted_classes: [ Date, Time ], aliases: true)
            meta = parsed.is_a?(Hash) ? parsed : {}
            text = body.to_s
          end
        end

        deck = meta["deck"].is_a?(Hash) ? meta["deck"] : meta.except("p2u", "version", "slides")
        slides = text.split(MARKDOWN_SEPARATOR).filter_map { |chunk| markdown_slide(chunk) }

        Manifest.new({ "p2u" => meta["p2u"] || meta["version"] || VERSION, "deck" => deck, "slides" => slides })
      end

      def markdown_slide(chunk)
        text = chunk.to_s.strip
        return if text.blank?

        if text.start_with?("# ")
          heading, body = split_heading(text)
          { "layout" => "section", "title" => heading, "body" => body.presence }.compact
        elsif text.start_with?("## ")
          heading, body = split_heading(text)
          { "layout" => "content", "title" => heading, "body" => body.presence }.compact
        else
          { "layout" => "content", "body" => text }
        end
      end

      def split_heading(text)
        lines = text.lines
        heading = lines.first.to_s.sub(/\A\#{1,6}\s*/, "").strip
        body = lines.drop(1).join.strip
        [ heading, body ]
      end
  end
end
