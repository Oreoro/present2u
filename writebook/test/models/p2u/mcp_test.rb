require "test_helper"
require "stringio"

class P2u::MCPTest < ActiveSupport::TestCase
  test "initialize returns server info" do
    response = P2u::MCP.handle({ "jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => {} })

    assert_equal "present2u", response.dig("result", "serverInfo", "name")
    assert_equal P2u::MCP::PROTOCOL_VERSION, response.dig("result", "protocolVersion")
  end

  test "tools/list advertises the compiler tools" do
    response = P2u::MCP.handle({ "jsonrpc" => "2.0", "id" => 2, "method" => "tools/list" })
    names = response.dig("result", "tools").map { |tool| tool["name"] }

    assert_includes names, "p2u_validate"
    assert_includes names, "p2u_export"
    assert_includes names, "p2u_apply"
  end

  test "tools/call validates a manifest" do
    response = P2u::MCP.handle({
      "jsonrpc" => "2.0", "id" => 3, "method" => "tools/call",
      "params" => { "name" => "p2u_validate", "arguments" => { "source" => valid_yaml } }
    })

    assert_equal false, response.dig("result", "isError")
    assert_includes response.dig("result", "content").first["text"], '"valid": true'
  end

  test "tools/call composes a manifest" do
    response = P2u::MCP.handle({
      "jsonrpc" => "2.0", "id" => 7, "method" => "tools/call",
      "params" => { "name" => "p2u_compose", "arguments" => { "prompt" => "a 4-slide deck on Raft", "slides" => 4 } }
    })

    assert_equal false, response.dig("result", "isError")
    assert_includes response.dig("result", "content").first["text"], '"valid": true'
  end

  test "tools/call reports an invalid manifest as an error" do
    response = P2u::MCP.handle({
      "jsonrpc" => "2.0", "id" => 4, "method" => "tools/call",
      "params" => { "name" => "p2u_validate", "arguments" => { "source" => "p2u: 1\ndeck:\n  title: T\nslides:\n  - layout: nope\n" } }
    })

    assert_equal true, response.dig("result", "isError")
    assert_includes response.dig("result", "content").first["text"], "unknown_layout"
  end

  test "unknown methods and tools return JSON-RPC errors" do
    method_error = P2u::MCP.handle({ "jsonrpc" => "2.0", "id" => 5, "method" => "nope" })
    tool_error = P2u::MCP.handle({ "jsonrpc" => "2.0", "id" => 6, "method" => "tools/call", "params" => { "name" => "nope" } })

    assert_equal(-32601, method_error.dig("error", "code"))
    assert_equal(-32602, tool_error.dig("error", "code"))
  end

  test "notifications produce no response" do
    assert_nil P2u::MCP.handle({ "jsonrpc" => "2.0", "method" => "notifications/initialized" })
  end

  test "start serves newline-delimited JSON over stdio" do
    input = StringIO.new({ "jsonrpc" => "2.0", "id" => 1, "method" => "ping" }.to_json + "\n")
    output = StringIO.new

    P2u::MCP.start(input: input, output: output)

    assert_equal 1, JSON.parse(output.string).dig("id")
  end

  private
    def valid_yaml
      <<~YAML
        p2u: 1
        deck:
          title: Raft
        slides:
          - layout: content
            body: Majority vote.
      YAML
    end
end
