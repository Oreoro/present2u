class Section < ApplicationRecord
  include Leafable

  def searchable_content
    body
  end

  def markable
    body
  end
end
