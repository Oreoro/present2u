class AddNotesToLeaves < ActiveRecord::Migration[8.0]
  def change
    add_column :leaves, :notes, :text
  end
end
