require "test_helper"

class P2u::ToolchainTest < ActiveSupport::TestCase
  test "reports the compiler stack" do
    report = P2u::Toolchain.report

    assert_equal P2u::VERSION, report.dig("p2u", "version")
    assert_equal "redcarpet", report.dig("markdown", "engine")
    assert_equal "rouge", report.dig("highlight", "engine")
    assert_equal "d2", report.dig("diagram", "engine")
    assert_includes report["layouts"], "content"
    assert_includes report["blocks"], "diagram"
  end
end
