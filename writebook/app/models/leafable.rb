module Leafable
  extend ActiveSupport::Concern

  TYPES = %w[ Page Section Picture Typst ]

  included do
    has_one :leaf, as: :leafable, inverse_of: :leafable, touch: true
    has_one :book, through: :leaf
    has_one :edit, as: :leafable

    delegate :title, to: :leaf
  end

  # Editing a page supersedes its leafable: the leaf moves on to a copy and the original
  # is kept by the edit that records the revision, so it no longer has a leaf of its own.
  # Its uploads are still served, so the book has to stay findable through the edit.
  def owning_book
    book || edit&.leaf&.book
  end

  def searchable_content
    nil
  end

  class_methods do
    def leafable_name
      @leafable_name ||= ActiveModel::Name.new(self).singular.inquiry
    end
  end

  def leafable_name
    self.class.leafable_name
  end
end
