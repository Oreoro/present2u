module P2u
  # Turns a manifest into an outline with per-slide metrics and a density
  # budget, so a person or agent can see how many slides a talk will need and
  # where it overflows before rendering anything.
  module Outliner
    ESTIMATED_SECONDS_PER_SLIDE = 45

    class << self
      def call(manifest)
        manifest = manifest.is_a?(Manifest) ? manifest : Manifest.new(manifest)

        slides = manifest.slides.each_with_index.map { |slide, index| slide_summary(slide, index) }
        words = slides.sum { |slide| slide[:words] }

        {
          title: manifest.deck["title"].presence || "Untitled deck",
          slide_count: slides.size,
          words: words,
          estimated_minutes: ((slides.size * ESTIMATED_SECONDS_PER_SLIDE) / 60.0).round,
          slides: slides
        }
      end

      private
        def slide_summary(slide, index)
          text = text_for(slide)
          words = text.scan(/\S+/).size
          bullets = text.scan(/^\s*(?:[-*+]|\d+\.)\s+/).size
          code_lines = code_lines_for(slide)

          {
            index: index + 1,
            id: slide["id"],
            layout: slide["layout"],
            title: slide["title"].presence || "Untitled",
            words: words,
            bullets: bullets,
            code_lines: code_lines,
            warnings: warnings_for(words, bullets, code_lines)
          }
        end

        def text_for(slide)
          parts = [ slide["body"].to_s ]
          Array(slide["blocks"]).each do |block|
            next unless block.is_a?(Hash)

            parts << block["body"].to_s
            parts << block["text"].to_s
            parts << block["source"].to_s if block["kind"].to_s == "markdown"
          end
          parts.join("\n")
        end

        def code_lines_for(slide)
          Array(slide["blocks"]).sum do |block|
            block.is_a?(Hash) && block["kind"].to_s == "code" ? block["source"].to_s.lines.size : 0
          end
        end

        def warnings_for(words, bullets, code_lines)
          warnings = []
          warnings << "dense (#{words} words)" if words > Validator::DENSITY[:words]
          warnings << "many bullets (#{bullets})" if bullets > Validator::DENSITY[:bullets]
          warnings << "long code (#{code_lines} lines)" if code_lines > Validator::DENSITY[:code_lines]
          warnings
        end
    end
  end
end
