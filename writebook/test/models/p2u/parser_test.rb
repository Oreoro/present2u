require "test_helper"

class P2u::ParserTest < ActiveSupport::TestCase
  test "parses a YAML manifest and derives slide ids" do
    manifest = P2u::Parser.parse(<<~YAML)
      p2u: 1
      deck:
        title: Raft
        theme: violet
      slides:
        - layout: section
          title: Raft
          body: Consensus
        - layout: content
          title: Leader election
          body: A leader is elected by a majority.
    YAML

    assert_equal "Raft", manifest.deck["title"]
    assert_equal 2, manifest.slides.size
    assert_equal "section", manifest.slides.first["layout"]
    assert_equal "leader-election-2", manifest.slides.last["id"]
  end

  test "parses a JSON manifest" do
    manifest = P2u::Parser.parse({ "deck" => { "title" => "JSON deck" }, "slides" => [ { "layout" => "content", "body" => "hi" } ] })

    assert_equal "JSON deck", manifest.deck["title"]
    assert_equal 1, manifest.slides.size
  end

  test "parses Markdown with front matter and slide separators" do
    manifest = P2u::Parser.parse(<<~MD)
      ---
      title: Transformer
      theme: violet
      ---

      # Attention

      The Transformer.

      ---

      ## Scaled dot-product attention

      Softmax of QK^T.
    MD

    assert_equal "Transformer", manifest.deck["title"]
    assert_equal 2, manifest.slides.size
    assert_equal "section", manifest.slides.first["layout"]
    assert_equal "Attention", manifest.slides.first["title"]
    assert_equal "content", manifest.slides.last["layout"]
    assert_equal "Scaled dot-product attention", manifest.slides.last["title"]
  end

  test "detects YAML that starts with the document marker" do
    manifest = P2u::Parser.parse("---\np2u: 1\ndeck:\n  title: Marker\nslides:\n  - layout: content\n    body: hi\n")

    assert_equal "Marker", manifest.deck["title"]
  end

  test "normalises legacy type into layout" do
    manifest = P2u::Parser.parse({ "deck" => { "title" => "Legacy" }, "slides" => [ { "type" => "divider", "title" => "One" }, { "type" => "page", "body" => "two" } ] })

    assert_equal "section", manifest.slides.first["layout"]
    assert_equal "content", manifest.slides.last["layout"]
  end

  test "raises ParseError on empty source" do
    assert_raises(P2u::ParseError) { P2u::Parser.parse("   ") }
  end

  test "raises ParseError on malformed JSON" do
    assert_raises(P2u::ParseError) { P2u::Parser.parse("{ nope", format: "json") }
  end
end
