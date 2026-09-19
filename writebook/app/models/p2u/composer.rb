module P2u
  # Turns a natural-language request ("a 12-slide technical deck on Raft
  # consensus with diagrams") into a valid P2U/1 manifest. Uses an
  # OpenAI-compatible LLM when configured, validating and repairing the result
  # against the compiler's diagnostics; otherwise falls back to a deterministic
  # outline built from the prompt and any supplied source notes.
  class Composer
    DEFAULT_SLIDES = 10
    MAX_REPAIRS = 2

    Result = Struct.new(:manifest, :diagnostics, :provider, :note, keyword_init: true) do
      def valid? = diagnostics.none?(&:error?)

      def to_h
        {
          valid: valid?,
          provider: provider,
          note: note,
          manifest: manifest&.to_h,
          diagnostics: diagnostics.map(&:to_h)
        }.compact
      end
    end

    def self.call(**arguments) = new(**arguments).compose

    def initialize(prompt:, sources: [], slides: nil, theme: nil, provider: nil)
      @prompt = prompt.to_s
      @sources = Array(sources).map(&:to_s).reject(&:blank?)
      @slides = slides&.to_i
      @theme = theme.presence
      @provider = provider.to_s.presence
    end

    def compose
      return heuristic_result(provider: "heuristic") unless use_llm?

      begin
        llm_result
      rescue P2u::LLM::Error => e
        heuristic_result(provider: "heuristic", note: "LLM unavailable: #{e.message}")
      end
    end

    private
      def use_llm?
        @provider != "heuristic" && P2u::LLM.configured?
      end

      def heuristic_result(provider:, note: nil)
        manifest = Manifest.new(Heuristic.new(prompt: @prompt, sources: @sources, slides: @slides, theme: @theme).to_manifest)
        Result.new(manifest: manifest, diagnostics: Validator.new(manifest).validate, provider: provider, note: note)
      end

      def llm_result
        manifest = nil
        diagnostics = []

        (0..MAX_REPAIRS).each do |attempt|
          content = P2u::LLM.complete(system: system_prompt, user: user_prompt(manifest, diagnostics))
          manifest = extract_manifest(content)
          diagnostics = Validator.new(manifest).validate
          break if diagnostics.none?(&:error?)

          Rails.logger.info("p2u compose: repair #{attempt + 1}") if defined?(Rails.logger)
        end

        Result.new(manifest: manifest, diagnostics: diagnostics, provider: "llm")
      rescue P2u::ParseError => e
        failure = Diagnostic.new(severity: "error", code: "compose_parse_error", message: e.message)
        Result.new(manifest: nil, diagnostics: [ failure ], provider: "llm")
      end

      def system_prompt
        <<~PROMPT
          You are the present2u compiler's author. Reply with ONLY a P2U/1 manifest
          (YAML or JSON). No prose, no code fences.

          Shape:
            p2u: 1
            deck: { title, subtitle?, author?, theme? }
            slides: [ { id?, layout, title?, subtitle?, body?, blocks?, notes?, theme?, sketch? } ]

          Layouts: #{Layouts.keys.join(', ')}.
          Block kinds: #{Blocks.keys.join(', ')} (diagram langs: #{Blocks::ENGINES.join(', ')}).
          `body` is Markdown and may contain inline $math$, fenced ```d2, ```d2-sketch and ```latex.
          Use `diagram`/`equation`/`code-split`/`metric-row`/`two-column` where they genuinely help.
          Include speaker `notes` on content slides. Aim for a clear narrative.
        PROMPT
      end

      def user_prompt(previous, diagnostics)
        parts = []
        parts << "Create a technical presentation."
        parts << "Topic / request: #{@prompt}." if @prompt.present?
        parts << "Target about #{target_count} slides."
        parts << "Theme: #{@theme}." if @theme.present?
        parts << "Base it on these notes:\n\n#{@sources.join("\n\n---\n\n")}" if @sources.any?

        if previous && diagnostics.any?(&:error?)
          parts << "Your previous manifest was invalid. Fix these and return the corrected manifest only:"
          parts << diagnostics.select(&:error?).map { |diagnostic| "- [#{diagnostic.code}] #{diagnostic.message}" }.join("\n")
        end

        parts.join("\n\n")
      end

      def extract_manifest(content)
        text = content.to_s.strip
        text = text.sub(/\A```[a-zA-Z]*[ \t]*\r?\n?/, "").sub(/\r?\n?```\s*\z/, "")

        P2u::Parser.parse(text)
      rescue P2u::ParseError
        fenced = content.to_s.match(/```[a-zA-Z]*[ \t]*\r?\n(.*?)```/m)
        raise unless fenced

        P2u::Parser.parse(fenced[1])
      end

      def target_count
        @slides || prompt_count || DEFAULT_SLIDES
      end

      def prompt_count
        @prompt[/\b(\d{1,3})\s*[- ]?slides?\b/i, 1]&.to_i
      end

    # Deterministic outline used when no LLM is configured (or it fails). With
    # source notes it derives slides from them; otherwise it scaffolds a
    # standard technical narrative for the topic.
    class Heuristic
      DEFAULT_SECTIONS = [
        { title: "Context", body: "Why this matters and the problem we're solving." },
        { title: "Background", body: "Prior art and the landscape." },
        { title: "Approach", body: "The core idea and how it works." },
        { title: "Architecture", body: "Components, data flow and interfaces." },
        { title: "Implementation", body: "Key decisions, code and trade-offs." },
        { title: "Results", body: "Measurements, benchmarks and evidence." },
        { title: "Evaluation", body: "How we know it works." },
        { title: "Limitations", body: "What is hard, and what comes next." },
        { title: "Conclusion", body: "Recap and takeaways." }
      ].freeze

      def initialize(prompt:, sources:, slides:, theme:)
        @prompt = prompt.to_s
        @sources = sources
        @slides = slides
        @theme = theme
      end

      def to_manifest
        {
          "p2u" => 1,
          "deck" => {
            "title" => topic,
            "subtitle" => "A technical overview",
            "theme" => @theme.presence || "violet"
          },
          "slides" => structure
        }
      end

      private
        def structure
          body = body_slides

          if target_count >= 8
            [ title_slide, agenda_slide(body) ] + body.first([ target_count - 4, 1 ].max) + [ recap_slide, qa_slide ]
          elsif target_count >= 4
            [ title_slide ] + body.first([ target_count - 2, 1 ].max) + [ qa_slide ]
          else
            [ title_slide ] + body.first([ target_count - 1, 0 ].max)
          end
        end

        def body_slides
          return generated_slides if @sources.empty?

          derived = @sources.flat_map { |source| source_slides(source) }
          derived = derived.reject { |slide| slide["layout"] == "title" }
          return generated_slides if derived.empty?

          pad(derived.map { |slide| normalize(slide) })
        end

        # A source may be a P2U manifest, a Markdown document with `---`
        # separators, or plain prose. Fall back to splitting on headings.
        def source_slides(source)
          manifest = P2u::Parser.parse(source)
          return manifest.slides if manifest.slides.any?

          split_by_headings(source)
        rescue P2u::ParseError
          split_by_headings(source)
        end

        def split_by_headings(source)
          text = source.to_s
          slides = text.split(/^(?=\#{1,3}\s+)/).filter_map do |segment|
            next if segment.strip.empty?

            if (match = segment.match(/\A\#{1,3}\s+(.+?)\s*\n(.*)\z/m))
              { "layout" => "content", "title" => match[1].strip, "body" => match[2].strip }
            else
              { "layout" => "content", "body" => segment.strip }
            end
          end

          slides.presence || [ { "layout" => "content", "body" => text.strip } ]
        end

        def normalize(slide)
          {
            "layout" => (slide["layout"] == "section" ? "section" : "content"),
            "title" => slide["title"].presence,
            "body" => slide["body"].presence,
            "blocks" => slide["blocks"].presence,
            "notes" => slide["notes"].presence
          }.compact
        end

        def pad(slides)
          return slides if slides.size >= target_count

          slides + generated_slides.first(target_count - slides.size)
        end

        def generated_slides
          count = [ target_count, 1 ].max

          count.times.map do |index|
            section = DEFAULT_SECTIONS[index % DEFAULT_SECTIONS.size]
            {
              "layout" => "content",
              "title" => section[:title],
              "body" => "#{section[:body]}\n\nHow it applies to **#{topic}**:\n\n- Point one\n- Point two\n- Point three"
            }
          end
        end

        def title_slide
          { "layout" => "title", "title" => topic, "subtitle" => "A technical overview" }
        end

        def agenda_slide(body)
          titles = body.filter_map { |slide| slide["title"] }.first(8)
          bullets = titles.any? ? titles.map { |title| "- #{title}" } : [ "- Overview" ]
          { "layout" => "content", "title" => "Agenda", "body" => bullets.join("\n") }
        end

        def recap_slide
          { "layout" => "recap", "title" => "Recap", "body" => "The key ideas, in one slide." }
        end

        def qa_slide
          { "layout" => "qa", "title" => "Questions", "body" => "Thank you." }
        end

        def target_count
          @slides || @prompt[/\b(\d{1,3})\s*[- ]?slides?\b/i, 1]&.to_i || DEFAULT_SLIDES
        end

        def topic
          text = @prompt.dup
          text = text.sub(/\A\s*(please\s+)?(make|create|build|generate|write|give\s+me|design|prepare)\s+(me\s+)?/i, "")
          text = text.gsub(/\b\d{1,3}\s*[- ]?slides?\b/i, "")
          text = text.gsub(/\b(deck|presentation|talk|slides?|technical|overview|introduction|intro)\b/i, "")
          text = text.sub(/\A\s*(a|an|the)\s+/i, "")
          text = text.gsub(/\b(on|about|for|covering|re:)\b/i, "")
          text = text.gsub(/\s+/, " ").strip
          text.presence || "Untitled talk"
        end
    end
  end
end
