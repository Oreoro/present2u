module P2u
  # A single compiler finding, addressable by slide and manifest path so an
  # agent can locate, explain and repair it.
  class Diagnostic
    SEVERITIES = %w[error warning info].freeze

    attr_reader :severity, :code, :message, :slide, :path, :hint

    def initialize(severity:, code:, message:, slide: nil, path: nil, hint: nil)
      @severity = severity.to_s
      raise ArgumentError, "Unknown severity: #{@severity}" unless SEVERITIES.include?(@severity)

      @code = code.to_s
      @message = message.to_s
      @slide = slide.presence
      @path = path.presence
      @hint = hint.presence
    end

    def error? = severity == "error"
    def warning? = severity == "warning"

    def to_h
      { severity:, code:, message:, slide:, path:, hint: }.compact
    end

    def to_s
      location = [ slide, path ].compact.join(" ")
      prefix = location.present? ? "#{location}: " : ""
      suffix = hint.present? ? " (#{hint})" : ""
      "#{severity.upcase} [#{code}] #{prefix}#{message}#{suffix}"
    end
  end
end
