require "optparse"
require "json"

module P2u
  # Command line front end for the P2U/1 compiler. Kept in app/models so it is
  # autoloaded and testable; bin/p2u is a thin wrapper that boots Rails.
  class CLI
    EXIT_OK = 0
    EXIT_ERROR = 1
    EXIT_USAGE = 2

    def self.start(argv) = new(argv).run

    def initialize(argv)
      @argv = argv.dup
      @options = { json: false, render: false, format: nil }
    end

    def run
      command = @argv.shift

      case command
      when "validate" then validate
      when "compile" then compile
      when "plan" then plan
      when "apply" then apply
      when "compose" then compose
      when "outline" then outline
      when "export" then export
      when "mcp" then mcp
      when "schema" then schema
      when "doctor", "toolchain" then doctor
      when "help", "-h", "--help", nil then usage
      else
        warn "Unknown command: #{command}"
        usage
        EXIT_USAGE
      end
    end

    private
      def validate
        file = parse_options!
        result = P2u::Compiler.compile(read(file), format: @options[:format])
        report(result, plan: false)
        result.valid? ? EXIT_OK : EXIT_ERROR
      end

      def compile
        file = parse_options!
        result = P2u::Compiler.compile(read(file), format: @options[:format], render: @options[:render])
        report(result, plan: true)
        result.valid? ? EXIT_OK : EXIT_ERROR
      end

      def plan
        file = parse_options!
        result = P2u::Planner.new(parse_manifest(read(file)), book: find_deck!).plan
        report_plan(result)
        result.valid? ? EXIT_OK : EXIT_ERROR
      end

      def apply
        file = parse_options!
        result = P2u::Planner.new(parse_manifest(read(file)), book: find_deck!).apply(user: find_user!)
        report_plan(result)
        result.valid? ? EXIT_OK : EXIT_ERROR
      end

      def compose
        prompt = parse_options!.to_s
        sources = Array(@options[:sources]).map { |path| File.read(path) }
        result = P2u::Composer.call(prompt: prompt, sources: sources, slides: @options[:slides], theme: @options[:theme])

        File.write(@options[:out], result.manifest.to_h.to_yaml) if @options[:out] && result.manifest

        if @options[:json]
          puts JSON.pretty_generate(result.to_h)
        else
          puts "#{result.valid? ? '✓' : '✗'} #{result.manifest&.deck&.dig('title') || 'Untitled'} — #{result.manifest&.slides&.size.to_i} slides (via #{result.provider})"
          puts "  note: #{result.note}" if result.note
          result.diagnostics.each { |diagnostic| puts "  #{diagnostic}" }
        end

        create_deck(result) if @options[:create] && result.valid?
        result.valid? ? EXIT_OK : EXIT_ERROR
      end

      def create_deck(result)
        book = P2u::Emitter.new(result.manifest).build!(user: find_user!)
        puts "created deck ##{book.id}: #{book.title}"
      end

      def outline
        file = parse_options!
        result = P2u::Outliner.call(parse_manifest(read(file)))

        if @options[:json]
          puts JSON.pretty_generate(result)
        else
          puts "#{result[:title]} — #{result[:slide_count]} slides, #{result[:words]} words, ~#{result[:estimated_minutes]} min"
          result[:slides].each do |slide|
            warning = slide[:warnings].any? ? "  ! #{slide[:warnings].join(', ')}" : ""
            puts format("  %2d. [%-11s] %-32s %4d words%s", slide[:index], slide[:layout], slide[:title][0, 32], slide[:words], warning)
          end
        end

        EXIT_OK
      end

      def export
        file = parse_options!
        exporter = P2u::Exporter.new(parse_manifest(read(file)))
        to = (@options[:to] || "html").to_s

        if to == "pdf"
          path = @options[:out] || exporter.filename("pdf")
          exporter.to_pdf(path)
          puts "wrote #{path}"
          return EXIT_OK
        end

        extension = to == "html" ? "html" : "md"
        content = to == "html" ? exporter.to_html : exporter.to_notes
        path = @options[:out] || exporter.filename(extension)
        File.write(path, content)
        puts "wrote #{path} (#{content.bytesize} bytes)"
        EXIT_OK
      rescue P2u::Exporter::Error => e
        warn "p2u: #{e.message}"
        EXIT_ERROR
      end

      def mcp
        parse_options!
        P2u::MCP.start
        EXIT_OK
      end

      def schema
        parse_options!
        puts JSON.pretty_generate(P2u.schema)
        EXIT_OK
      end

      def doctor
        parse_options!
        report = P2u::Toolchain.report

        if @options[:json]
          puts JSON.pretty_generate(report)
        else
          puts "present2u toolchain (P2U/#{P2u::VERSION})"
          puts "  markdown    #{report.dig('markdown', 'engine')} #{report.dig('markdown', 'version')}"
          puts "  highlight   #{report.dig('highlight', 'engine')} #{report.dig('highlight', 'version')}"
          puts "  math        #{report.dig('math', 'engine')}"
          puts "  diagram     #{report.dig('diagram', 'engine')} #{report.dig('diagram', 'version')} (#{available(report.dig('diagram', 'available'))})"
          puts "  latex       #{report.dig('latex', 'binary', 'version')} (#{available(report.dig('latex', 'binary', 'available'))})"
          puts "  converter   #{report.dig('latex', 'converter', 'version')} (#{available(report.dig('latex', 'converter', 'available'))})"
          puts "  layouts     #{report['layouts'].size}"
          puts "  blocks      #{report['blocks'].size}"
        end

        EXIT_OK
      end

      def usage
        puts <<~TEXT
          p2u — P2U/1 presentation compiler

          Usage:
            p2u validate FILE [--format json|yaml|markdown] [--json]
            p2u compile  FILE [--render] [--format ...] [--json]
            p2u plan     FILE --deck ID [--format ...] [--json]
            p2u apply    FILE --deck ID --user EMAIL [--format ...] [--json]
            p2u compose  "PROMPT" [--slides N] [--theme T] [--source FILE] [--out FILE] [--create --user EMAIL] [--json]
            p2u outline  FILE [--json]
            p2u export   FILE --to html|notes|pdf [--out PATH] [--format ...]
            p2u mcp
            p2u schema   [--json]
            p2u doctor   [--json]

          FILE may be "-" to read from stdin.
        TEXT
        EXIT_OK
      end

      def parse_options!
        parser = OptionParser.new do |opts|
          opts.on("--json", "Machine-readable JSON output") { @options[:json] = true }
          opts.on("--render", "Build diagrams and equations while compiling") { @options[:render] = true }
          opts.on("--format FORMAT", "Force source format: json, yaml or markdown") { |value| @options[:format] = value }
          opts.on("--deck ID", "Deck id for plan/apply") { |value| @options[:deck] = value }
          opts.on("--user EMAIL", "User to attribute an apply to") { |value| @options[:user] = value }
          opts.on("--to FORMAT", "Export target: html, notes or pdf") { |value| @options[:to] = value }
          opts.on("--out PATH", "Output path for export/compose") { |value| @options[:out] = value }
          opts.on("--slides N", "Target slide count for compose", Integer) { |value| @options[:slides] = value }
          opts.on("--theme THEME", "Theme for compose") { |value| @options[:theme] = value }
          opts.on("--source FILE", "Source notes for compose (repeatable)") { |value| (@options[:sources] ||= []) << value }
          opts.on("--create", "Create the composed deck") { @options[:create] = true }
          opts.on("-h", "--help", "Show help") { usage; exit EXIT_OK }
        end

        parser.parse!(@argv)
        @argv.shift
      end

      def read(file)
        return $stdin.read if file.nil? || file == "-"

        File.read(file)
      rescue Errno::ENOENT
        abort "p2u: file not found: #{file}"
      end

      def parse_manifest(source)
        P2u::Parser.parse(source, format: @options[:format])
      end

      def find_deck!
        id = @options[:deck] || abort("p2u: --deck ID is required")
        Book.find(id)
      rescue ActiveRecord::RecordNotFound
        abort "p2u: deck not found: #{id}"
      end

      def find_user!
        email = @options[:user] || abort("p2u: --user EMAIL is required to apply")
        User.active.find_by(email_address: email) || abort("p2u: user not found: #{email}")
      end

      def report_plan(result)
        if @options[:json]
          puts JSON.pretty_generate(result.to_h)
          return
        end

        result.diagnostics.each { |diagnostic| puts "  #{diagnostic}" }
        return unless result.valid?

        puts "plan for #{result.book.title}: #{result.summary.inspect}"
        result.actions.each do |action|
          line = "  - #{action.action} #{action.slide}"
          line += " #{action.changes.inspect}" if action.changes.present?
          puts line
        end
      end

      def report(result, plan:)
        if @options[:json]
          payload = result.to_h
          payload[:plan] = [] unless plan
          puts JSON.pretty_generate(payload)
          return
        end

        if result.manifest.nil?
          puts "✗ manifest could not be parsed"
        else
          deck = result.manifest.deck
          puts "#{result.valid? ? '✓' : '✗'} #{deck['title'].presence || 'Untitled deck'} — #{result.manifest.slides.size} slides"
        end

        result.diagnostics.each { |diagnostic| puts "  #{diagnostic}" }

        if plan && result.plan.any?
          puts "  render plan (#{result.plan.size} assets):"
          result.plan.each do |entry|
            state = entry[:rendered] ? "rendered" : "pending"
            puts "    - #{entry[:slide]} [#{entry[:kind]}] #{entry[:digest][0, 12]} (#{state})"
          end
        end
      end

      def available(value) = value ? "available" : "missing"
  end
end
