require "test_helper"

class TypstsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :kevin
  end

  test "create" do
    post book_typsts_path(books(:handbook), format: :turbo_stream)
    assert_response :success

    typst = Typst.last
    assert_equal "Typst slide", typst.title
    assert_equal books(:handbook), typst.leaf.book
    assert typst.source.present?
  end

  test "preview returns an svg for valid source" do
    skip "typst binary is not installed" unless typst_available?

    post preview_book_typsts_path(books(:handbook)), params: { source: "= Hi" }
    assert_response :success
    assert_match(/<svg/, response.body)
  end

  test "preview reports an error for invalid source" do
    post preview_book_typsts_path(books(:handbook)), params: { source: "#let x = " }
    assert_response :unprocessable_entity
  end

  private
    def typst_available?
      system("which typst > /dev/null 2>&1")
    end
end
