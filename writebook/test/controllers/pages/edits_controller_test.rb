require "test_helper"

class Pages::EditsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :kevin
  end

  test "show an edit" do
    leaves(:welcome_page).edit leafable_params: { body: "Completely new content" }

    get page_edit_url(leaves(:welcome_page), leaves(:welcome_page).edits.last)

    assert_response :success
    assert_select "p", /such a great handbook/
    assert_select "p", /Completely new content/
  end

  test "show latest edit" do
    leaves(:welcome_page).edit leafable_params: { body: "Updated" }

    get page_edit_url(leaves(:welcome_page), "latest")

    assert_response :success
    assert_select "p", /such a great handbook/
  end

  test "show sanitizes dangerous content in previous version" do
    leaf = books(:handbook).press Page.new(body: %(<img src=x onerror="alert(1)">)), title: "XSS Test"
    leaf.edit leafable_params: { body: "Clean content now" }

    get page_edit_url(leaf, leaf.edits.last)

    assert_response :success
    assert_match '<img src="x">', response.body
    assert_no_match(/onerror/, response.body)
  end

  test "a trashed page's history is not reachable" do
    leaf = leaves(:welcome_page)
    leaf.edit leafable_params: { body: "Embargoed announcement: Project X" }
    leaf.trashed!

    get page_edit_url(leaf, "latest")

    assert_response :not_found
  end

  test "a trashed page's history is not reachable by a reader either" do
    leaf = leaves(:welcome_page)
    leaf.edit leafable_params: { body: "Embargoed announcement: Project X" }
    leaf.trashed!

    sign_in :jz
    get page_edit_url(leaf, "latest")

    assert_response :not_found
  end

  test "a reader can't read a live page's history" do
    leaves(:welcome_page).edit leafable_params: { body: "Updated" }

    sign_in :jz
    get page_edit_url(leaves(:welcome_page), "latest")

    assert_response :forbidden
  end

  test "an editor can still read a live page's history" do
    leaves(:welcome_page).edit leafable_params: { body: "Updated" }

    get page_edit_url(leaves(:welcome_page), "latest")

    assert_response :success
  end

  test "a user with no access to the book gets nothing" do
    leaf = leaves(:welcome_page)
    leaf.edit leafable_params: { body: "Updated" }
    accesses(:jz_handbook).destroy!

    sign_in :jz
    get page_edit_url(leaf, "latest")

    assert_response :not_found
  end

  test "show sanitizes dangerous content in current version" do
    leaves(:welcome_page).edit leafable_params: { body: %(<img src=x onerror="alert(1)">) }

    get page_edit_url(leaves(:welcome_page), leaves(:welcome_page).edits.last)

    assert_response :success
    assert_match '<img src="x">', response.body
    assert_no_match(/onerror/, response.body)
  end
end
