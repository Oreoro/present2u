require "open3"
require "timeout"

module P2u
  # Reports the toolchain ("stack") the compiler will use, with versions and
  # availability. Powers `p2u doctor` and GET /api/toolchain so agents can pick
  # layouts and blocks that will actually render here.
  module Toolchain
    TIMEOUT = 5

    BINARIES = {
      "d2" => %w[--version],
      "pdflatex" => %w[--version],
      "pdftocairo" => %w[-v],
      "typst" => %w[--version]
    }.freeze

    class << self
      def report
        {
          "p2u" => { "version" => P2u::VERSION },
          "markdown" => { "engine" => "redcarpet", "client" => "markdown-it", "version" => gem_version("redcarpet") },
          "highlight" => { "engine" => "rouge", "version" => gem_version("rouge") },
          "math" => { "engine" => "katex" },
          "typst" => { "engine" => "typst" }.merge(binary("typst")),
          "diagram" => {
            "engine" => "d2",
            "layouts" => %w[tala elk dagre],
            "styles" => %w[default sketch]
          }.merge(binary("d2")),
          "latex" => {
            "engine" => "pdflatex",
            "binary" => binary("pdflatex"),
            "converter" => binary("pdftocairo")
          },
          "layouts" => Layouts.keys,
          "blocks" => Blocks.keys,
          "diagram_engines" => Blocks::ENGINES
        }
      end

      private
        def gem_version(name)
          Gem.loaded_specs[name]&.version&.to_s
        end

        def binary(name)
          args = BINARIES.fetch(name)
          stdout, status = Timeout.timeout(TIMEOUT) { Open3.capture2e(name, *args) }
          { "available" => status.success?, "version" => first_line(stdout) }
        rescue Timeout::Error
          { "available" => true, "version" => nil, "error" => "timed out" }
        rescue Errno::ENOENT
          { "available" => false, "version" => nil }
        end

        def first_line(output)
          output.to_s.lines.first.to_s.strip.presence
        end
    end
  end
end
