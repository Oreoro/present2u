require "test_helper"

class P2u::EmitterTest < ActiveSupport::TestCase
  test "builds a deck with section and content slides" do
    book = P2u::Emitter.build!(manifest, user: users(:david))

    assert_equal "Raft", book.title
    assert_equal 2, book.leaves.count
    assert_equal %w[Section Page], book.leaves.with_leafables.map { |leaf| leaf.leafable.class.name }
  end

  test "serialises diagram blocks back into d2 fences" do
    book = P2u::Emitter.build!(manifest, user: users(:david))
    body = book.leaves.with_leafables.find(&:page?).page.body.content.to_s

    assert_includes body, "```d2"
    assert_includes body, "leader -> follower"
  end

  test "carries notes and sketch onto the leaf" do
    book = P2u::Emitter.build!(manifest, user: users(:david))
    section = book.leaves.with_leafables.find(&:section?)

    assert_equal "Set up the problem.", section.notes
    assert_equal "dark", section.section.theme
  end

  private
    def manifest
      P2u::Parser.parse({
        "p2u" => 1,
        "deck" => { "title" => "Raft", "subtitle" => "Consensus", "theme" => "violet" },
        "slides" => [
          { "layout" => "section", "title" => "Raft", "body" => "Consensus", "notes" => "Set up the problem.", "theme" => "dark" },
          {
            "layout" => "diagram",
            "title" => "Leader election",
            "blocks" => [
              { "kind" => "markdown", "body" => "A **leader** is elected." },
              { "kind" => "diagram", "lang" => "d2", "source" => "leader -> follower" }
            ]
          }
        ]
      })
    end
end
