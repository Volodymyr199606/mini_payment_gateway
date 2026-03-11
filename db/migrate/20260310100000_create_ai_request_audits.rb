# frozen_string_literal: true

class CreateAiRequestAudits < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_request_audits, if_not_exists: true do |t|
      t.string :request_id, null: false
      t.string :endpoint, null: false
      t.references :merchant, null: true, foreign_key: true
      t.string :agent_key, null: false
      t.string :retriever_key
      t.string :composition_mode
      t.boolean :tool_used, null: false, default: false
      t.jsonb :tool_names, default: []
      t.boolean :fallback_used, null: false, default: false
      t.boolean :citation_reask_used, null: false, default: false
      t.boolean :memory_used, null: false, default: false
      t.boolean :summary_used, null: false, default: false
      t.jsonb :parsed_entities, default: {}
      t.jsonb :parsed_intent_hints, default: {}
      t.integer :citations_count, default: 0
      t.integer :retrieved_sections_count
      t.integer :latency_ms
      t.string :model_used
      t.boolean :success, null: false, default: true
      t.string :error_class
      t.string :error_message
      t.datetime :created_at, null: false
    end

    add_index :ai_request_audits, :request_id, if_not_exists: true
    add_index :ai_request_audits, :merchant_id, if_not_exists: true
    add_index :ai_request_audits, :agent_key, if_not_exists: true
    add_index :ai_request_audits, :success, if_not_exists: true
    add_index :ai_request_audits, :created_at, if_not_exists: true
  end
end
