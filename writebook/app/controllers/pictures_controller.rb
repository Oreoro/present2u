class PicturesController < LeafablesController
  private
    def default_leaf_params
      { title: "Image slide" }
    end

    def new_leafable
      Picture.new leafable_params
    end

    def leafable_params
      params.fetch(:picture, {}).permit(:image, :caption, :remote_image_url)
    end
end
