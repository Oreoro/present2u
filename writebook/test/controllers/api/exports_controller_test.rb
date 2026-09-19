require "test_helper"

class Api::ExportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = "test-api-token"
    users(:david).update!(api_token: @token)
  end

  test "exports a self-contained HTML deck" do
    post api_export_path, params: manifest, headers: auth, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal "html", body["format"]
    assert_equal "raft.html", body["filename"]
    assert_includes body["content"], "p2u-slide"
  end

  test "exports speaker notes as markdown" do
    post api_export_path, params: { source: manifest.to_json, source_format: "json", to: "notes" }, headers: auth, as: :json

    assert_response :success
    assert_includes response.parsed_body["content"], "# Raft"
  end

  test "rejects an unsupported format" do
    post api_export_path, params: { source: manifest.to_json, source_format: "json", to: "pptx" }, headers: auth, as: :json

    assert_response :unprocessable_entity
  end

  test "requires authentication" do
    post api_export_path, params: manifest, as: :json

    assert_response :unauthorized
  end

  private
    def auth = { "Authorization" => "Bearer #{@token}" }

    def manifest
      {
        "p2u" => 1,
        "deck" => { "title" => "Raft" },
        "slides" => [ { "layout" => "content", "title" => "Intro", "body" => "Majority vote." } ]
      }
    end
end
