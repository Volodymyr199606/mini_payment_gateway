class CreatePaymentIntents < ActiveRecord::Migration[7.1]
  def change
    create_table :payment_intents, if_not_exists: true do |t|
      t.references :merchant, null: false, foreign_key: true
      t.references :customer, null: false, foreign_key: true
      t.references :payment_method, null: true, foreign_key: true
      t.integer :amount_cents, null: false
      t.string :currency, null: false, default: "USD"
      t.string :status, null: false, default: "created"
      t.string :idempotency_key
      t.jsonb :metadata

      t.timestamps
    end

    add_index :payment_intents, [:merchant_id, :idempotency_key], unique: true, where: "idempotency_key IS NOT NULL", if_not_exists: true
    add_index :payment_intents, :status, if_not_exists: true
  end
end
