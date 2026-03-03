# frozen_string_literal: true

class CreateAiChatSessions < ActiveRecord::Migration[7.2]
  def change
    create_table :ai_chat_sessions do |t|
      t.references :merchant, null: false, foreign_key: true
      t.text :summary_text
      t.datetime :summary_updated_at

      t.timestamps
    end
  end
end
