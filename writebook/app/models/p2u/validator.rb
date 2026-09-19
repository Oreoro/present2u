module P2u
  # Validates a P2u::Manifest and returns a list of P2u::Diagnostic. Schema and
  # semantic checks plus a slide-density budget, so agents get actionable
  # feedback rather than an exception.
  class Validator
    THEMES = %w[writebook black blue green magenta orange violet white].freeze
    ASPECTS = %w[16:9 4:3 16:10].freeze

    DENSITY = {
      words: 220,
      bullets: 12,
      code_lines: 40,
      words_per_slide_target: 90
    }.freeze

    def self.validate(manifest) = new(manifest).validate

    def initialize(manifest)
      @manifest = manifest
      @diagnostics = []
    end

    def validate
      validate_version
      validate_deck
      validate_slides
      @diagnostics
    end

    private
      def error(code, message, **options) = add("error", code, message, **options)
      def warn(code, message, **options) = add("warning", code, message, **options)
      def info(code, message, **options) = add("info", code, message, **options)

      def add(severity, code, message, **options)
        @diagnostics << Diagnostic.new(severity: severity, code: code, message: message, **options)
      end

      def validate_version
        version = @manifest.version

        if version.blank?
          warn("missing_version", "No `p2u` version declared; assuming #{P2u::VERSION}.", path: "p2u")
        elsif version != P2u::VERSION
          error("unsupported_version", "Unsupported p2u version #{version.inspect}.", path: "p2u",
            hint: "This compiler implements P2U/#{P2u::VERSION}.")
        end
      end

      def validate_deck
        deck = @manifest.deck

        unless deck.is_a?(Hash)
          error("invalid_deck", "`deck` must be a mapping.", path: "deck")
          return
        end

        warn("missing_title", "Deck has no `title`; it will be published as “Untitled deck”.", path: "deck.title") if deck["title"].blank?
        validate_theme(deck["theme"])
        validate_aspect(deck["aspect"])
        validate_defaults(deck["defaults"])
      end

      def validate_theme(theme)
        name = theme.is_a?(Hash) ? theme["preset"] : theme
        return if name.blank?

        unless THEMES.include?(name.to_s)
          error("unknown_theme", "Unknown theme #{name.inspect}.", path: "deck.theme",
            hint: "Known themes: #{THEMES.join(', ')}.")
        end
      end

      def validate_aspect(aspect)
        return if aspect.blank? || ASPECTS.include?(aspect.to_s)

        error("unknown_aspect", "Unknown aspect ratio #{aspect.inspect}.", path: "deck.aspect",
          hint: "Known ratios: #{ASPECTS.join(', ')}.")
      end

      def validate_defaults(defaults)
        return unless defaults.is_a?(Hash)

        layout = defaults["layout"]
        if layout.present? && !Layouts.key?(layout)
          error("unknown_layout", "Unknown default layout #{layout.inspect}.", path: "deck.defaults.layout",
            hint: "Known layouts: #{Layouts.keys.join(', ')}.")
        end
      end

      def validate_slides
        slides = @manifest.slides

        if slides.empty?
          error("no_slides", "The manifest has no slides.", path: "slides")
          return
        end

        seen = {}
        slides.each_with_index do |slide, index|
          unless slide.is_a?(Hash)
            error("invalid_slide", "Slide must be a mapping.", path: "slides[#{index}]")
            next
          end

          slide_id = slide["id"]
          if seen[slide_id]
            error("duplicate_slide_id", "Slide id #{slide_id.inspect} is used more than once.",
              slide: slide_id, path: "slides[#{index}].id")
          end
          seen[slide_id] = true

          validate_slide(slide, index)
        end
      end

      def validate_slide(slide, index)
        slide_id = slide["id"]
        layout = slide["layout"]

        unless Layouts.key?(layout)
          error("unknown_layout", "Unknown layout #{layout.inspect}.",
            slide: slide_id, path: "slides[#{index}].layout",
            hint: "Known layouts: #{Layouts.keys.join(', ')}.")
          return
        end

        definition = Layouts.fetch(layout)
        validate_required_fields(slide, definition, index)
        validate_content(slide, definition, index)
        validate_slots(slide, definition, index)
        validate_blocks(slide, definition, index)
        validate_density(slide, index)
      end

      def validate_required_fields(slide, definition, index)
        Array(definition[:required]).each do |field|
          next if slide[field].present?

          error("missing_field", "Layout #{slide['layout'].inspect} requires `#{field}`.",
            slide: slide["id"], path: "slides[#{index}].#{field}")
        end
      end

      def validate_content(slide, definition, index)
        return unless definition[:content] == :required

        has_body = slide["body"].present?
        has_blocks = Array(slide["blocks"]).any? { |block| serialize_candidate?(block) }

        unless has_body || has_blocks
          error("missing_content", "Layout #{slide['layout'].inspect} requires `body` or `blocks`.",
            slide: slide["id"], path: "slides[#{index}]")
        end
      end

      def validate_slots(slide, definition, index)
        Array(definition[:slots]).each do |slot|
          next if slide[slot].present?

          error("missing_slot", "Layout #{slide['layout'].inspect} requires slot `#{slot}`.",
            slide: slide["id"], path: "slides[#{index}].#{slot}")
        end
      end

      def validate_blocks(slide, definition, index)
        blocks = slide["blocks"]
        return if blocks.blank?

        unless blocks.is_a?(Array)
          error("invalid_blocks", "`blocks` must be a list.", slide: slide["id"], path: "slides[#{index}].blocks")
          return
        end

        allowed = definition[:allowed_blocks]
        if definition[:require_block] && blocks.none? { |block| serialize_candidate?(block) }
          error("missing_block", "Layout #{slide['layout'].inspect} requires at least one block.",
            slide: slide["id"], path: "slides[#{index}].blocks")
        end

        blocks.each_with_index do |block, block_index|
          path = "slides[#{index}].blocks[#{block_index}]"

          unless block.is_a?(Hash)
            error("invalid_block", "Block must be a mapping.", slide: slide["id"], path: path)
            next
          end

          kind = block["kind"].to_s
          unless Blocks.key?(kind)
            error("unknown_block", "Unknown block kind #{kind.inspect}.", slide: slide["id"], path: "#{path}.kind",
              hint: "Known blocks: #{Blocks.keys.join(', ')}.")
            next
          end

          if allowed && !allowed.include?(kind)
            error("block_not_allowed", "Layout #{slide['layout'].inspect} does not allow a #{kind.inspect} block.",
              slide: slide["id"], path: "#{path}.kind", hint: "Allowed here: #{allowed.join(', ')}.")
          end

          validate_block(block, kind, path)
        end
      end

      def validate_block(block, kind, path)
        definition = Blocks.fetch(kind)

        Array(definition[:required]).each do |field|
          next if block[field].present?

          error("missing_block_field", "Block #{kind.inspect} requires `#{field}`.", path: "#{path}.#{field}")
        end

        if definition[:any].present? && definition[:any].none? { |field| block[field].present? }
          error("missing_block_field", "Block #{kind.inspect} requires one of #{definition[:any].join(', ')}.",
            path: path)
        end

        if kind == "diagram"
          engine = (block["lang"].presence || block["engine"].presence || "d2").to_s
          unless Blocks::ENGINES.include?(engine)
            error("unknown_engine", "Unknown diagram engine #{engine.inspect}.", path: "#{path}.lang",
              hint: "Known engines: #{Blocks::ENGINES.join(', ')}.")
          end
        end
      end

      def validate_density(slide, index)
        text = density_text(slide)
        words = text.scan(/\S+/).size
        bullets = text.scan(/^\s*(?:[-*+]|\d+\.)\s+/).size
        code_lines = code_line_count(slide)

        if words > DENSITY[:words]
          warn("slide_density", "Slide has #{words} words (budget #{DENSITY[:words]}).",
            slide: slide["id"], path: "slides[#{index}]",
            hint: "Consider splitting into two slides.")
        end

        if bullets > DENSITY[:bullets]
          warn("too_many_bullets", "Slide has #{bullets} bullet points (budget #{DENSITY[:bullets]}).",
            slide: slide["id"], path: "slides[#{index}]")
        end

        if code_lines > DENSITY[:code_lines]
          warn("code_density", "Slide has #{code_lines} lines of code (budget #{DENSITY[:code_lines]}).",
            slide: slide["id"], path: "slides[#{index}]",
            hint: "Consider a `full-code` slide or splitting the listing.")
        end
      end

      def density_text(slide)
        parts = [ slide["body"].to_s ]
        Array(slide["blocks"]).each do |block|
          next unless block.is_a?(Hash)

          parts << block["body"].to_s
          parts << block["text"].to_s
          parts << block["source"].to_s if block["kind"].to_s == "markdown"
        end
        parts.join("\n")
      end

      def code_line_count(slide)
        Array(slide["blocks"]).sum do |block|
          next 0 unless block.is_a?(Hash) && block["kind"].to_s == "code"

          block["source"].to_s.lines.size
        end
      end

      def serialize_candidate?(block)
        block.is_a?(Hash) && (block["body"].present? || block["source"].present? || block["kind"].present?)
      end
  end
end
