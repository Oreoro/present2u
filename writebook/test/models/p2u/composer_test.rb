require "test_helper"

class P2u::ComposerTest < ActiveSupport::TestCase
  test "composes a heuristic manifest with the requested slide count" do
    result = P2u::Composer.call(prompt: "a 6-slide technical deck on Raft consensus")

    assert result.valid?, result.diagnostics.map(&:to_s).join("\n")
    assert_equal "heuristic", result.provider
    assert_equal 6, result.manifest.slides.size
    assert_equal "Raft consensus", result.manifest.deck["title"]
  end

  test "derives slides from source notes" do
    result = P2u::Composer.call(prompt: "Raft consensus", sources: [ notes ], slides: 6)
    titles = result.manifest.slides.map { |slide| slide["title"] }

    assert result.valid?
    assert_includes titles, "Leader election"
    assert_includes titles, "Log replication"
  end

  test "uses the LLM when configured" do
    with_llm(valid_llm_manifest) do
      result = P2u::Composer.call(prompt: "Raft consensus", slides: 3)

      assert_equal "llm", result.provider
      assert result.valid?
      assert_equal "LLM deck", result.manifest.deck["title"]
    end
  end

  test "repairs an invalid LLM manifest using diagnostics" do
    responses = [ invalid_llm_manifest, valid_llm_manifest ]

    with_llm(->(*_args, **_kwargs) { responses.shift }) do
      result = P2u::Composer.call(prompt: "Raft consensus")

      assert_equal "llm", result.provider
      assert result.valid?
    end
  end

  test "falls back to heuristic when the LLM fails" do
    with_llm(->(*_args, **_kwargs) { raise P2u::LLM::Error, "boom" }) do
      result = P2u::Composer.call(prompt: "Raft consensus")

      assert_equal "heuristic", result.provider
      assert result.valid?
      assert_includes result.note, "boom"
    end
  end

  test "provider heuristic skips the LLM even when configured" do
    with_llm(->(*_args, **_kwargs) { raise "should not be called" }) do
      result = P2u::Composer.call(prompt: "Raft consensus", provider: "heuristic")

      assert_equal "heuristic", result.provider
    end
  end

  private
    def with_llm(response)
      original_configured = P2u::LLM.method(:configured?)
      original_complete = P2u::LLM.method(:complete)

      P2u::LLM.define_singleton_method(:configured?) { true }
      P2u::LLM.define_singleton_method(:complete) do |**kwargs|
        response.respond_to?(:call) ? response.call(**kwargs) : response
      end

      yield
    ensure
      P2u::LLM.define_singleton_method(:configured?, original_configured)
      P2u::LLM.define_singleton_method(:complete, original_complete)
    end

    def notes
      <<~MD
        # Leader election

        A leader is elected by a majority.

        ## Log replication

        The leader appends entries.
      MD
    end

    def valid_llm_manifest
      <<~YAML
        p2u: 1
        deck:
          title: LLM deck
          theme: violet
        slides:
          - layout: title
            title: LLM deck
          - layout: content
            title: One
            body: First slide.
      YAML
    end

    def invalid_llm_manifest
      <<~YAML
        p2u: 1
        deck:
          title: LLM deck
        slides:
          - layout: nope
      YAML
    end
end
