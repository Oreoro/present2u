require "test_helper"

class Api::CompilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = "test-api-token"
    users(:david).update!(api_token: @token)
  end

  test "compiles a manifest posted as JSON" do
    post api_compile_path, params: valid_manifest, headers: auth, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal true, body["valid"]
    assert_equal 2, body.dig("manifest", "slides").size
    assert_equal [], body["diagnostics"]
  end

  test "compiles a manifest posted as YAML source" do
    post api_compile_path, params: { source: valid_yaml, source_format: "yaml" }, headers: auth, as: :json

    assert_response :success
    assert_equal "Raft", response.parsed_body.dig("manifest", "deck", "title")
  end

  test "returns diagnostics and 422 for an invalid manifest" do
    post api_compile_path, params: { "deck" => { "title" => "x" }, "slides" => [ { "layout" => "nope" } ] },
      headers: auth, as: :json

    assert_response :unprocessable_entity
    body = response.parsed_body
    assert_equal false, body["valid"]
    assert_includes body["diagnostics"].map { |d| d["code"] }, "unknown_layout"
  end

  test "requires authentication" do
    post api_compile_path, params: valid_manifest, as: :json

    assert_response :unauthorized
  end

  private
    def auth = { "Authorization" => "Bearer #{@token}" }

    def valid_manifest
      {
        "p2u" => 1,
        "deck" => { "title" => "Raft", "theme" => "violet" },
        "slides" => [
          { "layout" => "section", "title" => "Raft" },
          { "layout" => "content", "title" => "Leader election", "body" => "Majority vote." }
        ]
      }
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
end
