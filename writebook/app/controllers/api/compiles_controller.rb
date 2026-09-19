module Api
  # Compile a P2U/1 manifest without persisting anything. Accepts either:
  #
  #   { "source": "p2u: 1\n...", "format": "yaml" }   # raw text
  #   <manifest JSON as the request body>               # structured manifest
  #
  # Returns diagnostics, the normalised manifest and a render plan. Pass
  # `render: true` to build diagrams/equations and get stable asset URLs.
  class CompilesController < BaseController
    # POST /api/compile
    def create
      result = P2u::Compiler.compile(source, format: source_format, render: render?)

      render json: result.to_h, status: result.valid? ? :ok : :unprocessable_entity
    end

    private
      def source
        params[:source].presence || request.raw_post.presence || "{}"
      end

      def source_format
        explicit = params[:source_format].presence || params[:format].presence
        return explicit.to_s if explicit.present?
        return "json" unless params[:source].present?

        nil
      end

      def render?
        ActiveModel::Type::Boolean.new.cast(params[:render]) || false
      end
  end
end
