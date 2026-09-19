# Turns an agent-friendly manifest (plain Ruby hashes from JSON) into a deck of
# slides. Used by the JSON API, the template library and the demo decks.
#
#   DeckBuilder.create!(user: user, manifest: {
#     deck: {
#       title: "Attention Is All You Need",
#       theme: "black",
#       slides: [
#         { type: "section", title: "Attention", body: "The Transformer", theme: "dark" },
#         { type: "content", title: "Scaled dot-product attention", body: "markdown..." },
#         { type: "image", title: "Figure", image_url: "https://...", caption: "..." }
#       ]
#     }
#   })
class DeckBuilder
  class Error < StandardError; end

  def self.create!(user:, manifest:)
    new(user).create!(manifest)
  end

  def initialize(user)
    @user = user
  end

  def create!(manifest)
    deck = normalize(manifest)

    Book.transaction do
      book = Book.create!(
        title: deck[:title].presence || "Untitled deck",
        subtitle: deck[:subtitle],
        author: deck[:author].presence || @user.name,
        theme: theme_for(deck[:theme])
      )
      book.update_access(readers: [], editors: [ @user.id ])
      Array(deck[:slides]).each { |slide| add_slide(book, slide) }
      book
    end
  end

  # Adds a single slide to an existing deck and returns its Leaf.
  def add_slide(book, slide)
    slide = slide.to_h.with_indifferent_access

    case slide[:type].to_s
    when "section", "divider"
      book.press Section.new(body: slide[:body].presence || slide[:title], theme: slide[:theme].presence),
        leaf_attributes(slide, "Section slide")
    when "image", "picture"
      book.press Picture.new(caption: slide[:caption], remote_image_url: slide[:image_url]),
        leaf_attributes(slide, "Image slide")
    when "typst"
      book.press Typst.new(source: slide[:source].presence || slide[:body].to_s),
        leaf_attributes(slide, "Typst slide")
    when "content", "page", ""
      book.press Page.new(body: slide[:body].to_s), leaf_attributes(slide, "Untitled")
    else
      raise Error, "Unknown slide type: #{slide[:type].inspect}"
    end
  end

  private
    def normalize(manifest)
      data = manifest.to_h.with_indifferent_access
      deck = (data[:deck].presence || data).dup
      deck[:slides] ||= data[:slides]
      deck
    end

    def leaf_attributes(slide, default_title)
      {
        title: slide[:title].presence || default_title,
        notes: slide[:notes],
        sketch: ActiveModel::Type::Boolean.new.cast(slide[:sketch]) || false,
        p2u_id: slide[:id].presence,
        layout: slide[:layout].presence || P2u::Layouts.resolve(slide[:type].presence || "content")
      }
    end

    def theme_for(theme)
      theme = theme.to_s
      Book.themes.key?(theme) ? theme : "black"
    end
end
