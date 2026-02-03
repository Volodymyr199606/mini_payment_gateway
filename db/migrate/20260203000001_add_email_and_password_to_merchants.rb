class AddEmailAndPasswordToMerchants < ActiveRecord::Migration[7.1]
  def change
    add_column :merchants, :email, :string
    add_column :merchants, :password_digest, :string
    add_index :merchants, :email, unique: true, where: "email IS NOT NULL AND email != ''"
  end
end
