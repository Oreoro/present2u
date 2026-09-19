# Builds the "E = mc²" reference deck from the template library and adds a
# context.dev figure, exercising every technical slide feature end to end.
class TechnicalDemo
  WIKI_URL = "https://en.wikipedia.org/wiki/Mass%E2%80%93energy_equivalence".freeze

  def self.create!(user)
    book = DeckBuilder.create!(user: user, manifest: DeckTemplates::Einstein.manifest)
    add_web_image(book)
    book
  end

  def self.add_web_image(book)
    return book unless ContextDev.configured?

    image = ContextDev.images(url: WIKI_URL).find { |candidate| candidate["width"].to_i >= 600 && candidate["kind"] != "icon" }
    return book unless image

    DeckBuilder.new(nil).add_slide(book, {
      type: "image",
      title: "Figure: mass–energy equivalence",
      caption: "Pulled from the web with context.dev",
      image_url: image["src"]
    })
    book
  rescue ContextDev::Error => e
    Rails.logger.warn("TechnicalDemo: skipping context.dev image (#{e.message})")
    book
  end
end
