module P2u
  # Parses, validates and plans a manifest. Compilation is pure unless
  # `render: true` is passed, in which case diagrams and equations are built
  # through RenderedAsset and their stable URLs are returned in the plan.
  class Compiler
    Result = Struct.new(:manifest, :diagnostics, :plan, :valid, keyword_init: true) do
      def valid? = !!valid
      def errors = diagnostics.select(&:error?)
      def warnings = diagnostics.select(&:warning?)

      def to_h
        {
          valid: valid?,
          version: P2u::VERSION,
          manifest: manifest&.to_h,
          diagnostics: diagnostics.map(&:to_h),
          plan: plan
        }.compact
      end
    end

    def self.compile(source, format: nil, render: false)
      manifest = source.is_a?(Manifest) ? source : Parser.parse(source, format: format)
      new(manifest).compile(render: render)
    rescue ParseError => e
      failure = Diagnostic.new(severity: "error", code: "parse_error", message: e.message)
      Result.new(manifest: nil, diagnostics: [ failure ], plan: [], valid: false)
    end

    def initialize(manifest)
      @manifest = manifest
    end

    def compile(render: false)
      diagnostics = Validator.new(@manifest).validate
      plan = []

      if diagnostics.none?(&:error?)
        plan = asset_requests.map do |request|
          compile_asset(request, render: render, diagnostics: diagnostics)
        end
      end

      Result.new(
        manifest: @manifest,
        diagnostics: diagnostics,
        plan: plan,
        valid: diagnostics.none?(&:error?)
      )
    end

    private
      # Every asset-producing block in the deck, in slide order.
      def asset_requests
        @manifest.slides.flat_map do |slide|
          Array(slide["blocks"]).filter_map do |block|
            next unless block.is_a?(Hash)

            case block["kind"].to_s
            when "diagram" then diagram_request(slide, block)
            when "equation" then { slide: slide["id"], kind: "latex", source: block["source"].to_s, options: {} }
            end
          end
        end
      end

      def diagram_request(slide, block)
        engine = (block["lang"].presence || block["engine"].presence || "d2").to_s
        return { slide: slide["id"], kind: "typst", source: block["source"].to_s, options: {} } if %w[typst typ].include?(engine)
        return unless %w[d2 d2-sketch tala].include?(engine)

        options = { layout: "tala", theme: 301, sketch: engine == "d2-sketch" }
        options.merge!(P2u.deep_stringify(block["options"]).symbolize_keys) if block["options"].is_a?(Hash)

        { slide: slide["id"], kind: "d2", source: block["source"].to_s, options: options }
      end

      def compile_asset(request, render:, diagnostics:)
        digest = RenderedAsset.digest_for(
          kind: request[:kind], source: request[:source], options: request[:options]
        )

        entry = {
          slide: request[:slide],
          kind: request[:kind],
          digest: digest,
          url: "/rendered/#{digest}.svg",
          rendered: false
        }

        if render
          begin
            entry[:url] = RenderedAsset.store(
              kind: request[:kind], source: request[:source], options: request[:options]
            )
            entry[:rendered] = true
          rescue StandardError => e
            diagnostics << Diagnostic.new(
              severity: "error", code: "render_failed", slide: request[:slide],
              message: "#{request[:kind]} render failed: #{e.message}"
            )
          end
        end

        entry
      end
  end
end
