require "digest"
require "fileutils"

# Content-addressed store for rendered slide assets (LaTeX equations and D2
# diagrams). Identical source renders once; the file is then served by
# RenderedAssetsController at a stable URL that survives HTML sanitizing.
class RenderedAsset
  DIRECTORY = Rails.root.join("storage/rendered")
  FILENAME_PATTERN = /\A[a-f0-9]{64}\.svg\z/

  class << self
    def store(kind:, source:, options: {})
      digest = digest_for(kind: kind, source: source, options: options)
      filename = "#{digest}.svg"
      path = DIRECTORY.join(filename)

      write(path, render(kind, source, options)) unless path.exist?

      "/rendered/#{filename}"
    end

    # Stable content address for a render, without doing the render. Used by the
    # compiler to publish a render plan before assets are built.
    def digest_for(kind:, source:, options: {})
      Digest::SHA256.hexdigest(cache_key(kind, source, options))
    end

    def file_for(filename)
      return unless filename.to_s.match?(FILENAME_PATTERN)

      DIRECTORY.join(filename)
    end

    private
      def cache_key(kind, source, options)
        normalized = options.to_h.map { |key, value| [ key.to_s, value.to_s ] }.sort
        [ kind.to_s, normalized.inspect, source.to_s ].join("\u0000")
      end

      def render(kind, source, options)
        case kind.to_s
        when "d2"    then D2Diagram.new(source, **options.symbolize_keys).to_svg
        when "latex" then LatexEquation.new(source, **options.symbolize_keys).to_svg
        when "typst"
          options = options.symbolize_keys
          slide = options.delete(:slide)
          options.delete(:theme)
          slide ? TypstDocument.slide(source, **options).to_svg : TypstDocument.new(source, **options).to_svg
        else raise ArgumentError, "Unknown rendered asset kind: #{kind}"
        end
      end

      def write(path, contents)
        FileUtils.mkdir_p(DIRECTORY)
        temporary = "#{path}.tmp.#{Process.pid}.#{Thread.current.object_id}"
        File.binwrite(temporary, contents)
        File.rename(temporary, path)
      ensure
        File.delete(temporary) if temporary && File.exist?(temporary)
      end
  end
end
