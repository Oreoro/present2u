# Proxies Context.dev image lookups so the browser never sees the API key.
class ContextDevController < ApplicationController
  def search
    unless ContextDev.configured?
      return render json: { error: "Context.dev is not configured. Set CONTEXT_DEV_API_KEY." },
        status: :service_unavailable
    end

    if params[:source_url].blank?
      return render json: { error: "Provide a page URL to look up." }, status: :unprocessable_entity
    end

    results =
      if params[:kind] == "screenshot"
        [ ContextDev.screenshot(url: params[:source_url]) ]
      else
        ContextDev.images(url: params[:source_url])
      end

    render json: { results: results }
  rescue ContextDev::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
