module P2u
  # A parsed, structurally-normalised manifest. Normalisation is intentionally
  # lenient about the legacy `type`/`body` shape so every existing deck and API
  # payload keeps compiling; the Validator still reports on the result.
  class Manifest
    attr_reader :data

    def initialize(data)
      @data = normalize(data)
    end

    def version = (@data["p2u"] || @data["version"]).to_s.presence
    def deck = @data["deck"] || {}
    def slides = Array(@data["slides"])
    def dig(*keys) = @data.dig(*keys)
    def to_h = @data

    private
      def normalize(data)
        hash = P2u.deep_stringify(data)
        hash = {} unless hash.is_a?(Hash)

        deck = hash["deck"].is_a?(Hash) ? hash["deck"] : {}
        slides = hash["slides"] || deck["slides"]
        slides = [] unless slides.is_a?(Array)

        hash["deck"] = deck
        hash["slides"] = slides.each_with_index.map { |slide, index| normalize_slide(slide, index) }
        hash
      end

      def normalize_slide(slide, index)
        slide = P2u.deep_stringify(slide)
        slide = {} unless slide.is_a?(Hash)

        slide["layout"] = Layouts.resolve(slide["layout"].presence || slide["type"].presence || Layouts.default)
        slide["id"] = slide["id"].presence || derive_id(slide, index)
        slide["blocks"] = normalize_blocks(slide["blocks"]) if slide.key?("blocks")
        slide
      end

      def normalize_blocks(blocks)
        return blocks unless blocks.is_a?(Array)

        blocks.map do |block|
          block = P2u.deep_stringify(block)
          block = {} unless block.is_a?(Hash)
          block["kind"] = (block["kind"].presence || block["type"].presence || "markdown").to_s.strip.downcase
          block
        end
      end

      def derive_id(slide, index)
        base = slide["title"].presence || slide["layout"].presence || "slide"
        "#{base.to_s.parameterize.presence || 'slide'}-#{index + 1}"
      end
  end
end
