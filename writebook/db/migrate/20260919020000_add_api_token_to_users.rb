class AddApiTokenToUsers < ActiveRecord::Migration[8.0]
  def up
    add_column :users, :api_token, :string
    add_index :users, :api_token, unique: true

    say_with_time "Generating API tokens" do
      User.reset_column_information
      User.find_each { |user| user.update_column(:api_token, SecureRandom.hex(24)) }
    end
  end

  def down
    remove_column :users, :api_token
  end
end
