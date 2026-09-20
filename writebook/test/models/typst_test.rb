require "test_helper"

class TypstTest < ActiveSupport::TestCase
  test "markable returns the source" do
    typst = Typst.new(source: "= Hello")

    assert_equal "= Hello", typst.markable
  end

  test "searchable_content escapes Typst angle brackets but stays html safe" do
    typst = Typst.new(source: "a < b")

    assert typst.searchable_content.html_safe?
    assert_equal "a &lt; b", typst.searchable_content
  end

  test "rendered_svg degrades to an error block for invalid source" do
    typst = Typst.new(source: "#let x = ")

    assert_match(/diagram-error/, typst.rendered_svg)
  end
end
