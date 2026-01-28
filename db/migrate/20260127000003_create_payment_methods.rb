class CreatePaymentMethods < ActiveRecord::Migration[7.1]
  def change
    create_table :payment_methods do |t|
      t.references :customer, null: false, foreign_key: true
      t.string :method_type, null: false
      t.string :last4
      t.string :brand
      t.integer :exp_month
      t.integer :exp_year
      t.string :token, null: false, index: { unique: true }

      t.timestamps
    end

    add_index :payment_methods, :customer_id
  end
end
