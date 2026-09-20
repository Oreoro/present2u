require "json"

module P2u
  # A Model Context Protocol server over stdio, so an agent (Claude, Codex,
  # opencode, …) can drive the whole presentation workflow as tools: compose,
  # validate, render, create, plan/apply, export and publish decks.
  #
  # Run with `bin/p2u mcp` (or the `bin/p2u-mcp` wrapper, which finds a modern
  # Ruby for you). Speaks newline-delimited JSON-RPC 2.0 on stdin/stdout.
  module MCP
    PROTOCOL_VERSION = "2024-11-05".freeze
    SERVER_NAME = "present2u".freeze

    SOURCE_SCHEMA = {
      "source" => { "type" => "string", "description" => "P2U/1 manifest (YAML, JSON or Markdown)." },
      "format" => { "type" => "string", "enum" => %w[json yaml markdown], "description" => "Force the source format." }
    }.freeze

    TOOLS = [
      { "name" => "p2u_guide",
        "description" => "Read the agent guide: the P2U/1 manifest language, layouts, blocks and worked examples. Call this first.",
        "inputSchema" => { "type" => "object", "properties" => {} } },
      { "name" => "p2u_get_schema",
        "description" => "Return the P2U/1 JSON Schema (for validating or generating manifests).",
        "inputSchema" => { "type" => "object", "properties" => {} } },
      { "name" => "p2u_validate",
        "description" => "Validate a manifest and return diagnostics (severity, code, slide, path).",
        "inputSchema" => { "type" => "object", "properties" => SOURCE_SCHEMA, "required" => %w[source] } },
      { "name" => "p2u_compile",
        "description" => "Parse, validate and plan a manifest; with render:true also builds diagram/equation SVGs.",
        "inputSchema" => { "type" => "object", "properties" => SOURCE_SCHEMA.merge("render" => { "type" => "boolean" }), "required" => %w[source] } },
      { "name" => "p2u_outline",
        "description" => "Summarise a manifest as an outline with per-slide word/code budgets — use it to check slide density.",
        "inputSchema" => { "type" => "object", "properties" => SOURCE_SCHEMA, "required" => %w[source] } },
      { "name" => "p2u_compose",
        "description" => "Turn a prompt (and optional source notes) into a validated P2U/1 manifest. Use provider:\"llm\" when P2U_LLM_API_KEY is set, else \"heuristic\".",
        "inputSchema" => { "type" => "object", "properties" => { "prompt" => { "type" => "string" }, "sources" => { "type" => "array", "items" => { "type" => "string" } }, "slides" => { "type" => "integer" }, "theme" => { "type" => "string" }, "provider" => { "type" => "string", "enum" => %w[heuristic llm] } }, "required" => %w[prompt] } },
      { "name" => "p2u_render",
        "description" => "Render a single diagram or equation to a cached SVG asset (d2, d2-sketch, latex or typst).",
        "inputSchema" => { "type" => "object", "properties" => { "kind" => { "type" => "string", "enum" => %w[d2 latex typst] }, "source" => { "type" => "string" }, "options" => { "type" => "object" } }, "required" => %w[kind source] } },
      { "name" => "p2u_export",
        "description" => "Export a manifest to a self-contained HTML deck, Markdown speaker notes, or a PDF (PDF requires out:).",
        "inputSchema" => { "type" => "object", "properties" => SOURCE_SCHEMA.merge("to" => { "type" => "string", "enum" => %w[html notes pdf] }, "out" => { "type" => "string" }), "required" => %w[source] } },
      { "name" => "p2u_list_templates",
        "description" => "List the built-in technical deck templates you can base a deck on.",
        "inputSchema" => { "type" => "object", "properties" => {} } },
      { "name" => "p2u_list_decks",
        "description" => "List decks in the workspace with id, title, slide count and URL.",
        "inputSchema" => { "type" => "object", "properties" => {} } },
      { "name" => "p2u_get_deck",
        "description" => "Read one deck: its outline and slide ids (for planning an update).",
        "inputSchema" => { "type" => "object", "properties" => { "deck_id" => { "type" => "integer" } }, "required" => %w[deck_id] } },
      { "name" => "p2u_create_deck",
        "description" => "Create a new deck from a manifest. Returns the deck id and URL.",
        "inputSchema" => { "type" => "object", "properties" => SOURCE_SCHEMA.merge("user" => { "type" => "string", "description" => "Email of the owning user (defaults to the first active user)." }), "required" => %w[source] } },
      { "name" => "p2u_compose_deck",
        "description" => "Agentic one-shot: compose a deck from a prompt and create it. Returns the deck id and URL.",
        "inputSchema" => { "type" => "object", "properties" => { "prompt" => { "type" => "string" }, "sources" => { "type" => "array", "items" => { "type" => "string" } }, "slides" => { "type" => "integer" }, "theme" => { "type" => "string" }, "provider" => { "type" => "string", "enum" => %w[heuristic llm] }, "user" => { "type" => "string" } }, "required" => %w[prompt] } },
      { "name" => "p2u_plan",
        "description" => "Diff a manifest against an existing deck (read-only) — like Terraform plan.",
        "inputSchema" => { "type" => "object", "properties" => SOURCE_SCHEMA.merge("deck_id" => { "type" => "integer" }), "required" => %w[source deck_id] } },
      { "name" => "p2u_apply",
        "description" => "Idempotently apply a manifest to an existing deck — create/update/delete/reorder by stable slide id.",
        "inputSchema" => { "type" => "object", "properties" => SOURCE_SCHEMA.merge("deck_id" => { "type" => "integer" }, "user" => { "type" => "string", "description" => "Email of the user to attribute the apply to." }), "required" => %w[source deck_id user] } },
      { "name" => "p2u_doctor",
        "description" => "Report the compiler toolchain and versions (d2, typst, pdflatex, …).",
        "inputSchema" => { "type" => "object", "properties" => {} } }
    ].freeze

    RESOURCES = [
      { "uri" => "p2u://guide", "name" => "Agent guide (llms.txt)", "mimeType" => "text/plain" },
      { "uri" => "p2u://skill", "name" => "Present2u skill", "mimeType" => "text/markdown" },
      { "uri" => "p2u://schema", "name" => "P2U/1 JSON Schema", "mimeType" => "application/json" }
    ].freeze

    class << self
      # Serve MCP over newline-delimited JSON on the given streams.
      def start(input: $stdin, output: $stdout)
        input.each_line do |line|
          line = line.strip
          next if line.empty?

          request = begin
            JSON.parse(line)
          rescue JSON::ParserError
            nil
          end
          next unless request

          response = handle(request)
          next unless response

          output.puts(JSON.generate(response))
          output.flush
        end
      end

      # Handle one JSON-RPC request. Returns a response hash, or nil for
      # notifications.
      def handle(request)
        id = request["id"]
        method = request["method"].to_s
        params = request["params"] || {}

        case method
        when "initialize"
          success(id, {
            "protocolVersion" => PROTOCOL_VERSION,
            "capabilities" => { "tools" => {}, "resources" => {} },
            "serverInfo" => { "name" => SERVER_NAME, "version" => P2u::VERSION },
            "instructions" => guide
          })
        when "notifications/initialized", "notifications/cancelled"
          nil
        when "ping"
          success(id, {})
        when "tools/list"
          success(id, { "tools" => TOOLS })
        when "tools/call"
          call_tool(id, params)
        when "resources/list"
          success(id, { "resources" => RESOURCES })
        when "resources/read"
          read_resource(id, params)
        else
          failure(id, -32601, "Method not found: #{method}")
        end
      rescue StandardError => e
        failure(id, -32603, e.message)
      end

      private
        def call_tool(id, params)
          name = params["name"].to_s
          arguments = params["arguments"] || {}

          handler = handlers[name]
          return failure(id, -32602, "Unknown tool: #{name}") unless handler

          text, is_error = handler.call(arguments)
          success(id, { "content" => [ { "type" => "text", "text" => text } ], "isError" => is_error })
        rescue StandardError => e
          success(id, { "content" => [ { "type" => "text", "text" => "Error: #{e.message}" } ], "isError" => true })
        end

        def read_resource(id, params)
          case params["uri"].to_s
          when "p2u://guide" then success(id, { "contents" => [ { "uri" => "p2u://guide", "mimeType" => "text/plain", "text" => guide } ] })
          when "p2u://skill" then success(id, { "contents" => [ { "uri" => "p2u://skill", "mimeType" => "text/markdown", "text" => skill } ] })
          when "p2u://schema" then success(id, { "contents" => [ { "uri" => "p2u://schema", "mimeType" => "application/json", "text" => json(P2u.schema) } ] })
          else failure(id, -32602, "Unknown resource: #{params['uri']}")
          end
        end

        def success(id, result) = { "jsonrpc" => "2.0", "id" => id, "result" => result }
        def failure(id, code, message) = { "jsonrpc" => "2.0", "id" => id, "error" => { "code" => code, "message" => message } }

        def parse(arguments)
          P2u::Parser.parse(arguments["source"], format: arguments["format"])
        end

        def json(payload) = JSON.pretty_generate(payload)

        def guide
          @guide ||= read_doc("llms.txt")
        end

        def skill
          @skill ||= read_doc("SKILL.md")
        end

        def read_doc(name)
          path = Rails.root.join(name)
          path = Rails.root.join("docs", name) unless path.exist?
          path.exist? ? path.read : "#{name} not found"
        end

        def user_for(arguments)
          email = arguments["user"].presence
          (email && User.active.find_by(email_address: email)) || User.active.ordered.first ||
            raise("No user found; create one first or pass user:")
        end

        def deck_payload(book)
          {
            id: book.id,
            title: book.title,
            subtitle: book.subtitle,
            slides: book.leaves.count,
            slug: book.slug,
            url: "/decks/#{book.id}/#{book.slug}",
            published: book.published?
          }
        end

        def handlers
          @handlers ||= {
            "p2u_guide" => ->(_args) { [ guide, false ] },
            "p2u_get_schema" => ->(_args) { [ json(P2u.schema), false ] },
            "p2u_validate" => ->(args) {
              result = P2u::Compiler.compile(args["source"], format: args["format"])
              [ json(result.to_h), !result.valid? ]
            },
            "p2u_compile" => ->(args) {
              result = P2u::Compiler.compile(args["source"], format: args["format"], render: !!args["render"])
              [ json(result.to_h), !result.valid? ]
            },
            "p2u_outline" => ->(args) { [ json(P2u::Outliner.call(parse(args))), false ] },
            "p2u_compose" => ->(args) {
              result = P2u::Composer.call(
                prompt: args["prompt"].to_s, sources: Array(args["sources"]),
                slides: args["slides"]&.to_i, theme: args["theme"], provider: args["provider"]
              )
              [ json(result.to_h), !result.valid? ]
            },
            "p2u_render" => ->(args) {
              url = RenderedAsset.store(kind: args["kind"], source: args["source"], options: (args["options"] || {}).symbolize_keys)
              [ json({ url: url }), false ]
            },
            "p2u_export" => ->(args) {
              exporter = P2u::Exporter.new(parse(args))
              to = (args["to"] || "html").to_s

              if to == "pdf"
                raise "PDF export needs out: (a file path)" if args["out"].blank?
                path = exporter.to_pdf(args["out"])
                [ json({ filename: File.basename(path), path: path, bytes: File.size(path) }), false ]
              else
                content = to == "notes" ? exporter.to_notes : exporter.to_html
                extension = to == "notes" ? "md" : "html"
                filename = exporter.filename(extension)

                if args["out"].present?
                  File.write(args["out"], content)
                  [ json({ filename: filename, bytes: content.bytesize, path: args["out"] }), false ]
                else
                  [ json({ filename: filename, bytes: content.bytesize, content: content }), false ]
                end
              end
            },
            "p2u_list_templates" => ->(_args) { [ json(DeckTemplate.all.map { |template| template.except(:manifest) }), false ] },
            "p2u_list_decks" => ->(_args) { [ json(Book.ordered.map { |book| deck_payload(book) }), false ] },
            "p2u_get_deck" => ->(args) {
              book = Book.find(args["deck_id"])
              leaves = book.leaves.positioned.map { |leaf| { id: leaf.id, p2u_id: leaf.p2u_id, layout: leaf.layout, title: leaf.title } }
              [ json(deck_payload(book).merge(slides_detail: leaves)), false ]
            },
            "p2u_create_deck" => ->(args) {
              manifest = parse(args)
              result = P2u::Compiler.new(manifest).compile
              raise result.errors.map(&:message).join("; ") unless result.valid?

              book = DeckBuilder.create!(user: user_for(args), manifest: manifest.to_h)
              [ json(deck_payload(book)), false ]
            },
            "p2u_compose_deck" => ->(args) {
              composed = P2u::Composer.call(
                prompt: args["prompt"].to_s, sources: Array(args["sources"]),
                slides: args["slides"]&.to_i, theme: args["theme"], provider: args["provider"]
              )
              raise composed.diagnostics.map(&:message).join("; ") unless composed.valid?

              book = DeckBuilder.create!(user: user_for(args), manifest: composed.manifest.to_h)
              [ json(deck_payload(book).merge(provider: composed.provider, note: composed.note)), false ]
            },
            "p2u_doctor" => ->(_args) { [ json(P2u::Toolchain.report), false ] },
            "p2u_plan" => ->(args) {
              result = P2u::Planner.new(parse(args), book: Book.find(args["deck_id"])).plan
              [ json(result.to_h), !result.valid? ]
            },
            "p2u_apply" => ->(args) {
              result = P2u::Planner.new(parse(args), book: Book.find(args["deck_id"])).apply(user: user_for(args))
              [ json(result.to_h), !result.valid? ]
            }
          }.freeze
        end
    end
  end
end
