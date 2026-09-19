module Api
  # Serves the P2U/1 JSON Schema so an agent can fetch the manifest contract as
  # a tool definition before emitting one.
  class SchemaController < BaseController
    # GET /api/schema
    def show
      render json: P2u.schema
    end
  end
end
