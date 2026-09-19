class Pages::EditsController < ApplicationController
  include PageLeafScoped

  before_action :ensure_editable
  before_action :set_edit

  def show
  end

  private
    # The only link to this screen lives in the page editor, which is already editor-gated,
    # so the interface has always expressed this restriction and the controller simply
    # didn't enforce it. Revision history shows text an editor removed from a page, which
    # a reader can't otherwise see even when the page itself is still readable.
    def ensure_editable
      head :forbidden unless @leaf.book.editable?
    end

    def set_edit
      if params[:id] == "latest"
        @edit = @leaf.edits.last
      else
        @edit = @leaf.edits.find(params[:id])
      end
    end
end
