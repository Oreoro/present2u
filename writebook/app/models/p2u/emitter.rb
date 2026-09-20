module P2u
  # Compiles a P2u::Manifest into the legacy slide shape DeckBuilder already
  # understands. Typed blocks are serialised back into Markdown fences so the
  # existing MarkdownRenderer (d2, d2-sketch, latex, Rouge) renders them with no
  # changes to the presentation runtime.
  class Emitter
    FENCED_BLOCKS = {
      "code" => "text",
      "diagram" => "d2",
      "equation" => "latex",
      "typst" => "typst"
    }.freeze

    def self.build!(manifest, user:)
      new(manifest).build!(user: user)
    end

    def initialize(manifest)
      @manifest = manifest.is_a?(Manifest) ? manifest : Manifest.new(manifest)
    end

    def deck_attributes
      deck = @manifest.deck
      {
        title: deck["title"].presence || "Untitled deck",
        subtitle: deck["subtitle"],
        author: deck["author"],
        theme: theme_name(deck["theme"])
      }
    end

    def slides
      format = deck_format
      @manifest.slides.map { |slide| slide_attributes(slide, format) }
    end

    def manifest
      { deck: deck_attributes.merge(slides: slides) }
    end

    def build!(user:)
      DeckBuilder.create!(user: user, manifest: manifest)
    end

    private
      def deck_format
        (@manifest.deck["format"].presence || @manifest.deck["engine"].presence || "markdown").to_s
      end

      def slide_attributes(slide, deck_format = "markdown")
        layout = slide["layout"].to_s
        base = {
          id: slide["id"],
          layout: layout,
          title: title_for(slide, layout),
          notes: slide["notes"].presence,
          sketch: ActiveModel::Type::Boolean.new.cast(slide["sketch"]) || false
        }

        format = (slide["format"].presence || deck_format).to_s
        return base.merge(type: "typst", source: slide["body"].to_s) if format == "typst"

        case layout
        when "section", "title"
          base.merge(type: "section", body: slide["body"].presence || slide["title"], theme: slide["theme"].presence)
        when "image", "image-grid"
          image = first_image(slide)
          base.merge(
            type: "image",
            caption: slide["caption"].presence || image["caption"].presence,
            image_url: image["url"].presence || image["src"].presence || image["image_url"].presence || slide["image_url"].presence
          )
        else
          base.merge(type: "content", body: body_for(slide))
        end
      end

      # Mirrors the defaults DeckBuilder applies so a plan/diff is stable.
      def title_for(slide, layout)
        slide["title"].presence || typst_heading(slide) || case layout
                                                           when "section", "title" then "Section slide"
                                                           when "image", "image-grid" then "Image slide"
                                                           else "Untitled"
                                                           end
      end

      # Use the first Typst heading (`= Title`) or a `#p2u-title("Title")` call as
      # the leaf title when none is given.
      def typst_heading(slide)
        body = slide["body"].to_s
        return body[/^[ \t]*=[ \t]+(.+?)[ \t]*$/, 1].strip if body.match?(/^[ \t]*=[ \t]+.+$/)

        body[/#p2u-title\(\s*"([^"]+)"/, 1]
      end

      def first_image(slide)
        Array(slide["blocks"]).find { |block| block.is_a?(Hash) && block["kind"].to_s == "image" } || {}
      end

      def body_for(slide)
        return slide["body"].to_s if slide["body"].present?

        blocks = Array(slide["blocks"]).map { |block| serialize_block(block) }
        slots = %w[left right code prose].filter_map { |slot| serialize_slot(slide[slot]) }
        (blocks + slots).reject(&:blank?).join("\n\n")
      end

      def serialize_slot(value)
        case value
        when Hash
          if value["kind"].present?
            serialize_block(value)
          else
            serialize_block(value.merge("kind" => "markdown"))
          end
        when String
          value
        end
      end

      def serialize_block(block)
        return block.to_s unless block.is_a?(Hash)

        block = P2u.deep_stringify(block)

        case block["kind"].to_s
        when "markdown" then block["body"].to_s
        when "code" then fenced(block["lang"].presence || "text", block["source"])
        when "diagram" then fenced(block["lang"].presence || "d2", block["source"])
        when "equation" then fenced("latex", block["source"])
        when "image" then "![#{block['alt'].presence || block['caption']}](#{block['url'].presence || block['src'].presence || block['image_url']})"
        when "quote" then quote_markdown(block)
        when "callout" then "> **#{block['tone'].presence || 'Note'}:** #{block['body']}"
        when "metric" then "**#{block['label']}:** #{block['value']}"
        when "definition" then "**#{block['term']}** — #{block['body']}"
        when "references" then Array(block["items"]).map { |item| "- #{item}" }.join("\n")
        when "table" then table_markdown(block)
        when "video" then "[#{block['title'].presence || 'Video'}](#{block['url']})"
        when "notes-only" then ""
        when "spacer" then "---"
        else block["body"].to_s
        end
      end

      def quote_markdown(block)
        lines = [ "> #{block['text']}" ]
        lines << "> — #{block['attribution']}" if block["attribution"].present?
        lines.join("\n")
      end

      def table_markdown(block)
        return block["markdown"].to_s if block["markdown"].present?
        return "" unless block["columns"].is_a?(Array) && block["rows"].is_a?(Array)

        header = "| #{block['columns'].join(' | ')} |"
        divider = "| #{block['columns'].map { '---' }.join(' | ')} |"
        rows = block["rows"].map { |row| "| #{Array(row).join(' | ')} |" }
        ([ header, divider ] + rows).join("\n")
      end

      def fenced(language, source)
        "```#{language}\n#{source}\n```"
      end

      def theme_name(theme)
        name = theme.is_a?(Hash) ? theme["preset"] : theme
        name.presence
      end
  end
end
