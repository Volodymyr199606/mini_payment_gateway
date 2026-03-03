# frozen_string_literal: true

class CreateAiChatMessages < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_chat_messages do |t|
      t.references :merchant, null: false, foreign_key: true
      t.string :role, null: false
      t.text :content, null: false
      t.string :agent

      t.timestamps
    end

    add_index :ai_chat_messages, [:merchant_id, :created_at]
  end
end
