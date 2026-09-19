module PageLeafScoped extend ActiveSupport::Concern
  included do
    before_action :set_leaf
  end

  private
    # Scoped to active leaves, like SetBookLeaf. Trashing a page records an edit that
    # keeps the old body, so without this a trashed page's whole content stayed readable
    # here even though the page itself 404s on its own URL.
    def set_leaf
      @leaf = Current.user.leaves.active.find(params[:page_id])
    end
end
