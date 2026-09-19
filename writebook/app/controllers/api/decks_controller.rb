module Api
  class DecksController < BaseController
    before_action :set_deck, only: %i[ show update destroy plan apply ]

    # GET /api/decks
    def index
      render json: { decks: accessible_decks.ordered.map { |deck| deck_json(deck) } }
    end

    # GET /api/decks/:id
    def show
      render json: { deck: deck_json(@deck, include_slides: true) }
    end

    # POST /api/decks
    # POST /api/decks/import  (same body; explicit bulk entry point)
    def create
      book = DeckBuilder.create!(user: current_user, manifest: { deck: manifest_params })
      render json: { deck: deck_json(book, include_slides: true) }, status: :created
    rescue DeckBuilder::Error => e
      render json: { error: e.message }, status: 422
    end

    alias_method :import, :create

    # PATCH /api/decks/:id
    def update
      return head :forbidden unless @deck.editable?(user: current_user)

      @deck.update!(deck_params)
      render json: { deck: deck_json(@deck, include_slides: true) }
    end

    # DELETE /api/decks/:id
    def destroy
      return head :forbidden unless @deck.editable?(user: current_user)

      @deck.destroy
      head :no_content
    end

    # POST /api/decks/:id/plan
    # Compute the diff between a desired manifest and the deck. Read-only.
    def plan
      return head :forbidden unless @deck.editable?(user: current_user)

      result = P2u::Planner.new(manifest, book: @deck).plan
      render json: result.to_h, status: result.valid? ? :ok : :unprocessable_entity
    end

    # POST /api/decks/:id/apply
    # Idempotently bring the deck in line with the manifest.
    def apply
      return head :forbidden unless @deck.editable?(user: current_user)

      result = P2u::Planner.new(manifest, book: @deck).apply(user: current_user)
      render json: result.to_h, status: result.valid? ? :ok : :unprocessable_entity
    end

    private
      def set_deck
        @deck = accessible_decks.find(params[:id])
      end

      def deck_params
        params.require(:deck).permit(:title, :subtitle, :author, :theme, :published)
      end

      # Accepts { "deck": { ... } } or a bare manifest at the top level.
      def manifest_params
        source = params[:deck].presence || params
        source.permit(:title, :subtitle, :author, :theme, :format, :layout,
          slides: [ :type, :title, :body, :source, :layout, :format, :notes, :sketch, :theme, :caption, :image_url ]).to_h
      end

      # A P2U/1 manifest for plan/apply, from `source` text or the JSON body.
      def manifest
        P2u::Parser.parse(plan_source, format: plan_format)
      end

      def plan_source
        params[:source].presence || request.raw_post.presence || "{}"
      end

      def plan_format
        explicit = params[:source_format].presence || params[:format].presence
        return explicit.to_s if explicit.present?
        return "json" unless params[:source].present?

        nil
      end
  end
end
