class AddSketchToLeaves < ActiveRecord::Migration[8.0]
  def change
    add_column :leaves, :sketch, :boolean, default: false, null: false
  end
end