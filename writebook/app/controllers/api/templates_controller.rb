module Api
  class TemplatesController < BaseController
    # GET /api/templates
    def index
      render json: { templates: DeckTemplate.all.map { |template| template.except(:manifest) } }
    end

    # POST /api/templates/:key  { "title": "optional override", "theme": "black" }
    def create
      template = DeckTemplate.find(params[:key])
      return render json: { error: "Unknown template" }, status: :not_found unless template

      manifest = template[:manifest].deep_dup
      manifest[:deck][:title] = params[:title] if params[:title].present?
      manifest[:deck][:theme] = params[:theme] if params[:theme].present?

      book = DeckBuilder.create!(user: current_user, manifest: manifest)
      render json: { deck: deck_json(book, include_slides: true) }, status: :created
    end
  end
end
