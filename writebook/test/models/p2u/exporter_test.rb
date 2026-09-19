require "test_helper"

class P2u::ExporterTest < ActiveSupport::TestCase
  test "to_html produces a self-contained document" do
    html = P2u::Exporter.new(P2u::Parser.parse(manifest)).to_html

    assert_includes html, "<!DOCTYPE html>"
    assert_includes html, "p2u-slide"
    assert_includes html, "Raft consensus"
    assert_includes html, "p2u-deck"
  end

  test "to_html renders every slide" do
    html = P2u::Exporter.new(P2u::Parser.parse(manifest)).to_html

    assert_equal 3, html.scan('class="p2u-slide ').size
  end

  test "to_notes emits markdown speaker notes" do
    notes = P2u::Exporter.new(P2u::Parser.parse(manifest)).to_notes

    assert_includes notes, "# Raft consensus"
    assert_includes notes, "Set up the problem."
    assert_includes notes, "_No speaker notes._"
  end

  test "filename is derived from the deck title" do
    assert_equal "raft-consensus.html", P2u::Exporter.new(P2u::Parser.parse(manifest)).filename("html")
  end

  private
    def manifest
      {
        "p2u" => 1,
        "deck" => { "title" => "Raft consensus", "theme" => "violet" },
        "slides" => [
          { "layout" => "section", "title" => "Raft", "notes" => "Set up the problem." },
          { "layout" => "content", "title" => "Election", "body" => "Majority vote." },
          { "layout" => "content", "title" => "Safety", "body" => "One leader per term." }
        ]
      }
    end
end
