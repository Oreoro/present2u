require "test_helper"

class P2u::Render::SlideTest < ActiveSupport::TestCase
  test "content layout renders a heading and markdown" do
    html = render(layout: "content", title: "Intro", body: "Hello **world**")

    assert_includes html, "p2u-heading"
    assert_includes html, "<strong>world</strong>"
  end

  test "two-column splits the slots" do
    html = render(layout: "two-column", title: "Compare", left: "Left side", right: "Right side")

    assert_includes html, "p2u-columns--two-column"
    assert_includes html, "Left side"
    assert_includes html, "Right side"
  end

  test "metric-row renders metric cards" do
    html = render(layout: "metric-row", blocks: [ { "kind" => "metric", "value" => "99.9%", "label" => "uptime" } ])

    assert_includes html, "p2u-metric__value"
    assert_includes html, "99.9%"
    assert_includes html, "uptime"
  end

  test "quote layout renders the quote and attribution" do
    html = render(layout: "quote", blocks: [ { "kind" => "quote", "text" => "Simplicity wins", "attribution" => "Someone" } ])

    assert_includes html, "p2u-quote"
    assert_includes html, "Simplicity wins"
    assert_includes html, "Someone"
  end

  test "image block renders a figure with a caption" do
    html = render(layout: "image", blocks: [ { "kind" => "image", "url" => "https://example.com/a.png", "caption" => "A picture" } ])

    assert_includes html, "<img"
    assert_includes html, "https://example.com/a.png"
    assert_includes html, "A picture"
  end

  test "sanitizes raw HTML authored in markdown" do
    html = render(layout: "content", body: "before <script>alert(1)</script> after")

    refute_includes html, "<script>"
    assert_includes html, "before"
  end

  private
    def render(slide)
      P2u::Render::Slide.new(P2u.deep_stringify(slide)).to_html
    end
end
