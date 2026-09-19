require "test_helper"

class Api::SchemaControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = "test-api-token"
    users(:david).update!(api_token: @token)
  end

  test "serves the P2U/1 JSON Schema" do
    get api_schema_path, headers: { "Authorization" => "Bearer #{@token}" }

    assert_response :success
    body = response.parsed_body
    assert_equal "P2U/1 presentation manifest", body["title"]
    assert_includes body.dig("$defs", "layout", "enum"), "content"
  end

  test "requires authentication" do
    get api_schema_path

    assert_response :unauthorized
  end
end
