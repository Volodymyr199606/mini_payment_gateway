class CreateTransactions < ActiveRecord::Migration[7.1]
  def change
    create_table :transactions, if_not_exists: true do |t|
      t.references :payment_intent, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :status, null: false
      t.integer :amount_cents, null: false
      t.string :processor_ref
      t.string :failure_code
      t.string :failure_message

      t.timestamps
    end

    add_index :transactions, :kind, if_not_exists: true
    add_index :transactions, :status, if_not_exists: true
    add_index :transactions, :processor_ref, if_not_exists: true
  end
end
