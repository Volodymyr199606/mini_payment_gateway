class CreateIdempotencyRecords < ActiveRecord::Migration[7.1]
  def change
    create_table :idempotency_records do |t|
      t.references :merchant, null: false, foreign_key: true
      t.string :idempotency_key, null: false
      t.string :endpoint, null: false
      t.string :request_hash, null: false
      t.jsonb :response_body, null: false
      t.integer :status_code, null: false

      t.timestamps
    end

    add_index :idempotency_records, [:merchant_id, :idempotency_key, :endpoint], 
              unique: true, 
              name: "index_idempotency_on_merchant_key_endpoint"
  end
end
