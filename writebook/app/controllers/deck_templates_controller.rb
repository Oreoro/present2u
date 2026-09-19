# One-click creation of a deck from the technical template library.
class DeckTemplatesController < ApplicationController
  def index
    @templates = DeckTemplate.all
  end

  def create
    template = DeckTemplate.find(params[:key])
    return redirect_to deck_templates_path, alert: "That template doesn't exist." unless template

    book = DeckBuilder.create!(user: Current.user, manifest: template[:manifest].deep_dup)
    redirect_to book_slug_path(book), notice: "Created “#{book.title}” from #{template[:title]}."
  end
end
