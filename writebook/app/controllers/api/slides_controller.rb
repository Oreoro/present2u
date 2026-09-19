module Api
  class SlidesController < BaseController
    before_action :set_deck
    before_action :ensure_editable
    before_action :set_leaf, only: %i[ update destroy ]

    # POST /api/decks/:deck_id/slides
    def create
      leaf = DeckBuilder.new(current_user).add_slide(@deck, slide_params.to_h)
      render json: { slide: slide_json(leaf) }, status: :created
    rescue DeckBuilder::Error => e
      render json: { error: e.message }, status: 422
    end

    # PATCH /api/decks/:deck_id/slides/:id
    def update
      @leaf.edit(leafable_params: leafable_params, leaf_params: leaf_params)
      render json: { slide: slide_json(@leaf.reload) }
    end

    # DELETE /api/decks/:deck_id/slides/:id
    def destroy
      @leaf.trashed!
      head :no_content
    end

    private
      def set_deck
        @deck = accessible_decks.find(params[:deck_id])
      end

      def set_leaf
        @leaf = @deck.leaves.active.find(params[:id])
      end

      def ensure_editable
        head :forbidden unless @deck.editable?(user: current_user)
      end

      def slide_params
        params.require(:slide).permit(:type, :title, :body, :source, :notes, :sketch, :theme, :caption, :image_url)
      end

      def leaf_params
        params.fetch(:slide, {}).permit(:title, :notes, :sketch)
      end

      def leafable_params
        slide = params.fetch(:slide, {})

        if @leaf.page?
          slide.permit(:body)
        elsif @leaf.section?
          slide.permit(:body, :theme)
        elsif @leaf.typst?
          slide.permit(:source)
        elsif @leaf.picture?
          permitted = slide.permit(:caption, :image_url)
          { caption: permitted[:caption], remote_image_url: permitted[:image_url] }.compact
        else
          {}
        end
      end
  end
end
