require "test_helper"

class Api::ToolchainControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = "test-api-token"
    users(:david).update!(api_token: @token)
  end

  test "reports the compiler toolchain" do
    get api_toolchain_path, headers: { "Authorization" => "Bearer #{@token}" }

    assert_response :success
    toolchain = response.parsed_body["toolchain"]
    assert_equal "redcarpet", toolchain.dig("markdown", "engine")
    assert_equal "d2", toolchain.dig("diagram", "engine")
    assert_includes toolchain["layouts"], "diagram"
  end

  test "requires authentication" do
    get api_toolchain_path

    assert_response :unauthorized
  end
end
