# Serves cached LaTeX/D2 renders. Content is addressed by digest and generated
# from slide source, so it is safe to serve publicly and cache aggressively.
class RenderedAssetsController < ApplicationController
  allow_unauthenticated_access

  def show
    file = RenderedAsset.file_for(params[:filename])
    return head :not_found unless file&.exist?

    response.headers["X-Content-Type-Options"] = "nosniff"
    expires_in 1.year, public: true
    send_file file, type: "image/svg+xml", disposition: "inline"
  end
end
