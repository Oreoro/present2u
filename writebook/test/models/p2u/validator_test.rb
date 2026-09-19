require "test_helper"

class P2u::ValidatorTest < ActiveSupport::TestCase
  test "a well-formed manifest has no errors" do
    diagnostics = P2u::Validator.validate(valid_manifest)

    assert_empty diagnostics.select(&:error?), diagnostics.map(&:to_s).join("\n")
  end

  test "reports an unknown layout" do
    diagnostics = validate_slides([ { "layout" => "nope", "title" => "x" } ])

    assert_includes codes(diagnostics), "unknown_layout"
  end

  test "reports a missing required field" do
    diagnostics = validate_slides([ { "layout" => "section" } ])

    assert_includes codes(diagnostics), "missing_field"
  end

  test "reports missing content for a content layout" do
    diagnostics = validate_slides([ { "layout" => "content", "title" => "empty" } ])

    assert_includes codes(diagnostics), "missing_content"
  end

  test "reports duplicate slide ids" do
    diagnostics = validate_slides([
      { "layout" => "content", "id" => "dup", "body" => "one" },
      { "layout" => "content", "id" => "dup", "body" => "two" }
    ])

    assert_includes codes(diagnostics), "duplicate_slide_id"
  end

  test "reports an unknown theme" do
    manifest = P2u::Parser.parse({ "deck" => { "title" => "x", "theme" => "chartreuse" }, "slides" => [ { "layout" => "content", "body" => "x" } ] })
    diagnostics = P2u::Validator.validate(manifest)

    assert_includes codes(diagnostics), "unknown_theme"
  end

  test "reports an unknown block kind" do
    diagnostics = validate_slides([ { "layout" => "content", "blocks" => [ { "kind" => "hologram" } ] } ])

    assert_includes codes(diagnostics), "unknown_block"
  end

  test "reports an unknown diagram engine" do
    diagnostics = validate_slides([ { "layout" => "diagram", "blocks" => [ { "kind" => "diagram", "source" => "a -> b", "lang" => "napkin" } ] } ])

    assert_includes codes(diagnostics), "unknown_engine"
  end

  test "warns when a slide is over the density budget" do
    diagnostics = validate_slides([ { "layout" => "content", "body" => ("word " * 260) } ])

    assert_includes codes(diagnostics), "slide_density"
  end

  test "accepts legacy type and body without errors" do
    manifest = P2u::Parser.parse({ "deck" => { "title" => "Legacy" }, "slides" => [ { "type" => "content", "body" => "Hello" } ] })

    assert_empty P2u::Validator.validate(manifest).select(&:error?)
  end

  private
    def valid_manifest
      P2u::Parser.parse({
        "p2u" => 1,
        "deck" => { "title" => "Test", "theme" => "violet" },
        "slides" => [
          { "layout" => "section", "title" => "Intro" },
          { "layout" => "content", "title" => "Body", "body" => "Hello $x^2$" }
        ]
      })
    end

    def validate_slides(slides)
      P2u::Validator.validate(P2u::Parser.parse({ "p2u" => 1, "deck" => { "title" => "T" }, "slides" => slides }))
    end

    def codes(diagnostics) = diagnostics.map(&:code)
end
