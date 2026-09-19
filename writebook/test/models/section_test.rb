require "test_helper"

class SectionTest < ActiveSupport::TestCase
  test "markable returns body content" do
    section = Section.new(body: "Section Content")

    assert_equal "Section Content", section.markable
  end

  test "markable returns nil when body is nil" do
    section = Section.new(body: nil)

    assert_nil section.markable
  end
end
