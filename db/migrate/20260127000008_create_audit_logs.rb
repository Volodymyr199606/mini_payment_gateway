class CreateAuditLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :audit_logs, if_not_exists: true do |t|
      t.references :merchant, null: true, foreign_key: true
      t.string :actor_type, null: false
      t.string :actor_id
      t.string :action, null: false
      t.string :auditable_type
      t.string :auditable_id
      t.jsonb :metadata

      t.timestamps
    end

    add_index :audit_logs, [:actor_type, :actor_id], if_not_exists: true
    add_index :audit_logs, [:auditable_type, :auditable_id], if_not_exists: true
    add_index :audit_logs, :action, if_not_exists: true
  end
end
