require "test_helper"

class P2u::OutlinerTest < ActiveSupport::TestCase
  test "summarises a manifest" do
    result = P2u::Outliner.call(P2u::Parser.parse(manifest))

    assert_equal "Raft", result[:title]
    assert_equal 2, result[:slide_count]
    assert_equal 1, result[:slides].first[:index]
    assert_operator result[:estimated_minutes], :>=, 1
  end

  test "counts words and warns on dense slides" do
    result = P2u::Outliner.call(P2u::Parser.parse(manifest))
    dense = result[:slides].last

    assert(dense[:warnings].any? { |warning| warning.include?("dense") }, dense[:warnings].inspect)
  end

  private
    def manifest
      {
        "p2u" => 1,
        "deck" => { "title" => "Raft" },
        "slides" => [
          { "layout" => "section", "title" => "Raft" },
          { "layout" => "content", "body" => ("word " * 260) }
        ]
      }
    end
end
