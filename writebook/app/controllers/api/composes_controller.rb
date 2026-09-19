module Api
  # Compose a P2U/1 manifest from a natural-language prompt (and optional
  # source notes). Uses an LLM when configured, otherwise a deterministic
  # outline. Pass `create: true` to build the deck in one step.
  class ComposesController < BaseController
    # POST /api/compose
    def create
      result = P2u::Composer.call(
        prompt: params[:prompt].to_s,
        sources: sources,
        slides: params[:slides].presence&.to_i,
        theme: params[:theme].presence,
        provider: params[:provider].presence
      )

      payload = result.to_h

      if create? && result.valid?
        book = P2u::Emitter.new(result.manifest).build!(user: current_user)
        payload[:deck] = { id: book.id, slug: book.slug, url: book_slug_url(book) }
      end

      render json: payload, status: result.valid? ? :ok : :unprocessable_entity
    end

    private
      def sources
        value = params[:sources]
        value.is_a?(Array) ? value.map(&:to_s) : Array(value).map(&:to_s)
      end

      def create?
        ActiveModel::Type::Boolean.new.cast(params[:create]) || false
      end
  end
end
