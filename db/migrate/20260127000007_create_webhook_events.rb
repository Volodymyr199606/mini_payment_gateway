class CreateWebhookEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :webhook_events do |t|
      t.references :merchant, null: true, foreign_key: true
      t.string :event_type, null: false
      t.jsonb :payload, null: false
      t.string :signature
      t.datetime :delivered_at
      t.string :delivery_status, default: "pending", null: false
      t.integer :attempts, default: 0, null: false

      t.timestamps
    end

    add_index :webhook_events, :merchant_id
    add_index :webhook_events, :event_type
    add_index :webhook_events, :delivery_status
  end
end
