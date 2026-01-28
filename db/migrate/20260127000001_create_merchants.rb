class CreateMerchants < ActiveRecord::Migration[7.1]
  def change
    create_table :merchants do |t|
      t.string :name, null: false
      t.string :api_key_digest, null: false, index: { unique: true }
      t.string :status, default: "active", null: false

      t.timestamps
    end

    add_index :merchants, :status
  end
end
