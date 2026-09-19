require "test_helper"

class P2u::CompilerTest < ActiveSupport::TestCase
  test "compiles a valid manifest" do
    result = P2u::Compiler.compile(valid_source)

    assert result.valid?
    assert_empty result.errors
    assert_equal 2, result.manifest.slides.size
  end

  test "plans assets for diagrams and equations without rendering" do
    result = P2u::Compiler.compile(source_with_assets)

    assert result.valid?, result.errors.map(&:to_s).join("\n")
    assert_equal 2, result.plan.size
    assert_equal %w[d2 latex], result.plan.map { |entry| entry[:kind] }
    assert(result.plan.all? { |entry| entry[:digest].match?(/\A[a-f0-9]{64}\z/) })
    assert(result.plan.none? { |entry| entry[:rendered] })
  end

  test "reports invalid manifests without a plan" do
    result = P2u::Compiler.compile({ "deck" => { "title" => "x" }, "slides" => [ { "layout" => "nope" } ] })

    refute result.valid?
    assert_empty result.plan
    assert_includes result.diagnostics.map(&:code), "unknown_layout"
  end

  test "reports parse errors as diagnostics" do
    result = P2u::Compiler.compile("{ nope", format: "json")

    refute result.valid?
    assert_equal "parse_error", result.diagnostics.first.code
  end

  private
    def valid_source
      {
        "p2u" => 1,
        "deck" => { "title" => "Raft", "theme" => "violet" },
        "slides" => [
          { "layout" => "section", "title" => "Raft" },
          { "layout" => "content", "title" => "Leader election", "body" => "Majority vote." }
        ]
      }
    end

    def source_with_assets
      {
        "p2u" => 1,
        "deck" => { "title" => "Assets" },
        "slides" => [
          {
            "layout" => "diagram",
            "title" => "Flow",
            "blocks" => [ { "kind" => "diagram", "source" => "a -> b" } ]
          },
          {
            "layout" => "equation",
            "title" => "Attention",
            "blocks" => [ { "kind" => "equation", "source" => "E = mc^2" } ]
          }
        ]
      }
    end
end
