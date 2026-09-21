module P2u
  # Builds a P2U/1 manifest from a deck (a Book and its leaves). This lets an
  # existing deck be exported, diffed or re-published through the compiler,
  # and is the inverse of P2u::Emitter (manifest -> deck).
  #
  #   P2u::DeckManifest.from(book)
  #   P2u::DeckManifest.from(book, url_for: ->(attachment) { ... })
  class DeckManifest
    THEMES = %w[ white black blue green magenta orange violet ].freeze

    def self.from(book, url_for: nil) = new(book, url_for: url_for).to_h

    def initialize(book, url_for: nil)
      @book = book
      @url_for = url_for
    end

    def to_h
      {
        "p2u" => 1,
        "deck" => {
          "title" => @book.title,
          "subtitle" => @book.subtitle,
          "author" => @book.author,
          "theme" => theme
        },
        "slides" => @book.leaves.positioned.filter_map { |leaf| slide_for(leaf) }
      }
    end

    private
      def theme
        name = @book.theme.to_s
        THEMES.include?(name) ? name : "white"
      end

      def slide_id(leaf) = leaf.p2u_id.presence || "slide-#{leaf.id}"

      def slide_for(leaf)
        base = { "id" => slide_id(leaf), "title" => leaf.title }
        base["notes"] = leaf.notes if leaf.notes.present?

        case leaf.leafable_name.to_s
        when "section"
          base.merge("layout" => "section", "body" => leaf.section.body.to_s)
        when "picture"
          image = leaf.picture
          block = { "kind" => "image", "caption" => image.caption.to_s.presence }.compact
          if image.image.attached? && @url_for
            block["url"] = @url_for.call(image.image)
          end
          base.merge("layout" => "image", "blocks" => [ block ])
        when "typst"
          base.merge("layout" => "content", "body" => "```typst\n#{leaf.typst.source}\n```")
        else
          base.merge("layout" => "content", "body" => leaf.page.body.content.to_s)
        end
      end
  end
end
