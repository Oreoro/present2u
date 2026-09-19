require "test_helper"

class P2u::PlannerTest < ActiveSupport::TestCase
  setup do
    @user = users(:david)
  end

  test "plans creates for an empty deck" do
    result = plan(Book.create!(title: "Empty"), manifest)

    assert result.valid?
    assert_equal 2, result.summary["create"]
    assert_equal 1, result.summary["reorder"]
  end

  test "is idempotent against a deck built from the same manifest" do
    book = P2u::Emitter.build!(manifest, user: @user)
    result = plan(book, manifest)

    assert result.valid?
    assert_empty result.actions
  end

  test "detects a title change" do
    book = P2u::Emitter.build!(manifest, user: @user)
    result = plan(book, changed_manifest)

    update = result.actions.find { |action| action.action == "update" }
    assert update, result.actions.inspect
    assert_equal [ "Raft", "Raft (revised)" ], update.changes["title"]
  end

  test "detects a delete" do
    book = P2u::Emitter.build!(manifest, user: @user)
    result = plan(book, without_second_slide)

    assert_equal 1, result.summary["delete"]
  end

  test "detects a reorder" do
    book = P2u::Emitter.build!(manifest, user: @user)
    result = plan(book, reordered_manifest)

    assert_equal 1, result.summary["reorder"]
  end

  test "apply builds the deck and a second plan is empty" do
    book = Book.create!(title: "Empty")
    P2u::Planner.new(manifest, book: book).apply(user: @user)

    assert_equal 2, book.leaves.active.count
    assert_empty plan(book, manifest).actions
  end

  test "apply updates an existing slide" do
    book = P2u::Emitter.build!(manifest, user: @user)
    P2u::Planner.new(changed_manifest, book: book).apply(user: @user)

    assert_equal "Raft (revised)", book.leaves.active.find_by(p2u_id: "intro").title
  end

  private
    def plan(book, source)
      P2u::Planner.new(P2u::Parser.parse(source), book: book).plan
    end

    def manifest
      {
        "p2u" => 1,
        "deck" => { "title" => "Raft", "theme" => "violet" },
        "slides" => [
          { "layout" => "section", "id" => "intro", "title" => "Raft", "body" => "Consensus" },
          { "layout" => "content", "id" => "election", "title" => "Election", "body" => "Majority vote." }
        ]
      }
    end

    def changed_manifest
      deep_dup = Marshal.load(Marshal.dump(manifest))
      deep_dup["slides"][0]["title"] = "Raft (revised)"
      deep_dup
    end

    def without_second_slide
      { "p2u" => 1, "deck" => { "title" => "Raft" }, "slides" => [ manifest["slides"][0] ] }
    end

    def reordered_manifest
      { "p2u" => 1, "deck" => { "title" => "Raft" }, "slides" => [ manifest["slides"][1], manifest["slides"][0] ] }
    end
end
