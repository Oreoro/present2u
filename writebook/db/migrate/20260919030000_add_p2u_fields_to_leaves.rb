class AddP2uFieldsToLeaves < ActiveRecord::Migration[8.0]
  def change
    add_column :leaves, :p2u_id, :string
    add_column :leaves, :layout, :string
    add_index :leaves, [ :book_id, :p2u_id ]
  end
end
