class CreateLedgerEntries < ActiveRecord::Migration[7.1]
  def change
    create_table :ledger_entries do |t|
      t.references :merchant, null: false, foreign_key: true
      t.references :transaction, null: true, foreign_key: true
      t.string :entry_type, null: false
      t.integer :amount_cents, null: false
      t.string :currency, null: false, default: "USD"

      t.timestamps
    end

    add_index :ledger_entries, :merchant_id
    add_index :ledger_entries, :transaction_id
    add_index :ledger_entries, :entry_type
  end
end
