require "test_helper"

class Api::DecksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = "test-api-token"
    @user = users(:david)
    @user.update!(api_token: @token)
    @book = P2u::Emitter.build!(manifest, user: @user)
  end

  test "plan reports a diff without changing the deck" do
    post plan_api_deck_path(@book), params: changed_manifest, headers: auth, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal 1, body.dig("summary", "update")
    assert_equal "Raft", @book.reload.title
  end

  test "apply updates the deck and the next plan is empty" do
    post apply_api_deck_path(@book), params: changed_manifest, headers: auth, as: :json

    assert_response :success
    assert_equal "Raft (revised)", @book.leaves.active.find_by(p2u_id: "intro").title

    post plan_api_deck_path(@book), params: changed_manifest, headers: auth, as: :json
    assert_response :success
    assert_empty response.parsed_body["actions"]
  end

  test "returns 422 for an invalid manifest" do
    post plan_api_deck_path(@book), params: { "deck" => { "title" => "x" }, "slides" => [ { "layout" => "nope" } ] },
      headers: auth, as: :json

    assert_response :unprocessable_entity
    assert_equal false, response.parsed_body["valid"]
  end

  test "requires authentication" do
    post plan_api_deck_path(@book), params: manifest, as: :json

    assert_response :unauthorized
  end

  private
    def auth = { "Authorization" => "Bearer #{@token}" }

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
end
