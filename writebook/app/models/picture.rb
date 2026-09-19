class Picture < ApplicationRecord
  include Leafable

  # Set from the Context.dev image picker. Downloaded and attached on save so
  # both new and edited slides can pull imagery straight from the web.
  attr_accessor :remote_image_url

  has_one_attached :image do |attachable|
    attachable.variant :large, resize_to_limit: [ 1500, 1500 ]
  end

  before_save :attach_remote_image, if: -> { remote_image_url.present? && !image.attached? }

  def large_image
    image.variable? ? image.variant(:large) : image
  end

  def markable
    caption
  end

  private
    def attach_remote_image
      download = ContextDev.download_image(remote_image_url)
      image.attach(io: download[:io], filename: download[:filename], content_type: download[:content_type])
      self.remote_image_url = nil
    rescue ContextDev::Error => e
      errors.add(:remote_image_url, e.message)
      throw :abort
    end
end
