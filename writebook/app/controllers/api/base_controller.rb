module Api
  # JSON API for agents and scripts. Authenticate with a user's API token:
  #
  #   Authorization: Bearer <api_token>
  class BaseController < ActionController::API
    before_action :authenticate_api_user

    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
    rescue_from ActiveRecord::RecordInvalid, with: :render_invalid
    rescue_from ActionController::ParameterMissing, with: :render_bad_request
    rescue_from P2u::ParseError, with: :render_parse_error

    private
      attr_reader :current_user

      def authenticate_api_user
        token = request.headers["Authorization"].to_s.split(" ").last
        @current_user = User.active.find_by(api_token: token) if token.present?
        Current.user = @current_user

        unless @current_user
          render json: { error: "Unauthorized. Send 'Authorization: Bearer <api_token>'." }, status: :unauthorized
        end
      end

      def accessible_decks
        Book.where(id: current_user.books.ids).or(Book.where(everyone_access: true)).distinct
      end

      def deck_json(book, include_slides: false)
        payload = {
          id: book.id,
          slug: book.slug,
          title: book.title,
          subtitle: book.subtitle,
          author: book.author,
          theme: book.theme,
          published: book.published,
          slide_count: book.leaves.active.count,
          url: book_slug_url(book),
          slides_url: api_deck_slides_url(book)
        }
        payload[:slides] = book.leaves.active.with_leafables.positioned.map { |leaf| slide_json(leaf) } if include_slides
        payload
      end

      def slide_json(leaf)
        {
          id: leaf.id,
          p2u_id: leaf.p2u_id,
          type: leaf.leafable_name.to_s,
          layout: leaf.layout,
          title: leaf.title,
          position: leaf.position_score,
          notes: leaf.notes,
          sketch: leaf.sketch?,
          body: body_for(leaf),
          source: (leaf.typst.source if leaf.typst?),
          caption: (leaf.picture.caption if leaf.picture?),
          theme: (leaf.section.theme if leaf.section?),
          url: leafable_slug_url(leaf)
        }.compact
      end

      def body_for(leaf)
        if leaf.page?
          leaf.page.body.content.to_s
        elsif leaf.section?
          leaf.section.body
        elsif leaf.typst?
          leaf.typst.source
        end
      end

      def render_not_found
        render json: { error: "Not found" }, status: :not_found
      end

      def render_invalid(error)
        render json: { error: error.record.errors.full_messages.to_sentence }, status: 422
      end

      def render_bad_request(error)
        render json: { error: error.message }, status: :bad_request
      end

      def render_parse_error(error)
        render json: { error: error.message, valid: false }, status: :unprocessable_entity
      end
  end
end
