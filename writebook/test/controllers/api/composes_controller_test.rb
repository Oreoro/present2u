require "test_helper"

class Api::ComposesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = "test-api-token"
    @user = users(:david)
    @user.update!(api_token: @token)
  end

  test "composes a manifest from a prompt" do
    post api_compose_path, params: { prompt: "a 6-slide technical deck on Raft consensus" }, headers: auth, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal true, body["valid"]
    assert_equal "heuristic", body["provider"]
    assert_equal 6, body.dig("manifest", "slides").size
  end

  test "creates the deck when asked" do
    assert_difference -> { Book.count }, 1 do
      post api_compose_path, params: { prompt: "Raft consensus", create: true }, headers: auth, as: :json
    end

    assert_response :success
    assert response.parsed_body.dig("deck", "id").present?
  end

  test "requires authentication" do
    post api_compose_path, params: { prompt: "Raft" }, as: :json

    assert_response :unauthorized
  end

  private
    def auth = { "Authorization" => "Bearer #{@token}" }
end
