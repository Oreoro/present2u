class CreateTypsts < ActiveRecord::Migration[8.2]
  def change
    create_table :typsts do |t|
      t.text :source

      t.timestamps
    end
  end
end
