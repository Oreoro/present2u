require "test_helper"
require "tempfile"
require "tmpdir"

class P2u::CLITest < ActiveSupport::TestCase
  test "validate exits 0 and reports slide count for a valid manifest" do
    output, = capture_io { @code = P2u::CLI.start([ "validate", file(valid_yaml) ]) }

    assert_equal 0, @code
    assert_includes output, "Raft"
    assert_includes output, "2 slides"
  end

  test "validate exits 1 and prints diagnostics for an invalid manifest" do
    output, = capture_io { @code = P2u::CLI.start([ "validate", file(invalid_yaml) ]) }

    assert_equal 1, @code
    assert_includes output, "unknown_layout"
  end

  test "compile --json emits machine-readable output" do
    output, = capture_io { @code = P2u::CLI.start([ "compile", file(valid_yaml), "--json" ]) }

    assert_equal 0, @code
    assert_equal true, JSON.parse(output)["valid"]
  end

  test "plan reports a diff for a deck" do
    book = P2u::Emitter.build!(manifest, user: users(:david))
    output, = capture_io { @code = P2u::CLI.start([ "plan", file(manifest.to_yaml), "--deck", book.id.to_s, "--json" ]) }

    assert_equal 0, @code
    assert_equal true, JSON.parse(output)["valid"]
  end

  test "apply brings a deck in line with a manifest" do
    book = Book.create!(title: "Empty")
    output, = capture_io do
      @code = P2u::CLI.start([ "apply", file(manifest.to_yaml), "--deck", book.id.to_s, "--user", "david@example.com" ])
    end

    assert_equal 0, @code
    assert_includes output, "plan for Empty"
    assert_equal 2, book.leaves.active.count
  end

  test "compose produces a manifest from a prompt" do
    output, = capture_io { @code = P2u::CLI.start([ "compose", "a 5-slide technical deck on Raft consensus", "--json" ]) }

    assert_equal 0, @code
    body = JSON.parse(output)
    assert_equal true, body["valid"]
    assert_equal 5, body.dig("manifest", "slides").size
  end

  test "export writes a self-contained HTML deck" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "deck.html")
      output, = capture_io { @code = P2u::CLI.start([ "export", file(manifest.to_yaml), "--to", "html", "--out", path ]) }

      assert_equal 0, @code
      assert_includes output, "wrote"
      assert_includes File.read(path), "p2u-slide"
    end
  end

  test "outline reports slide metrics" do
    output, = capture_io { @code = P2u::CLI.start([ "outline", file(manifest.to_yaml) ]) }

    assert_equal 0, @code
    assert_includes output, "2 slides"
  end

  test "schema prints the JSON Schema" do
    output, = capture_io { @code = P2u::CLI.start([ "schema" ]) }

    assert_equal 0, @code
    assert_equal "P2U/1 presentation manifest", JSON.parse(output)["title"]
  end

  test "doctor prints the toolchain" do
    output, = capture_io { @code = P2u::CLI.start([ "doctor", "--json" ]) }

    assert_equal 0, @code
    assert_equal "redcarpet", JSON.parse(output).dig("markdown", "engine")
  end

  private
    def file(contents)
      tempfile = Tempfile.new([ "deck", ".p2u" ])
      tempfile.write(contents)
      tempfile.close
      tempfile.path
    end

    def valid_yaml
      <<~YAML
        p2u: 1
        deck:
          title: Raft
        slides:
          - layout: section
            title: Raft
          - layout: content
            body: Majority vote.
      YAML
    end

    def invalid_yaml
      <<~YAML
        p2u: 1
        deck:
          title: Broken
        slides:
          - layout: nope
      YAML
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
end
