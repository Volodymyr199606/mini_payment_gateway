# frozen_string_literal: true

class AddAiChatSessionToAiChatMessages < ActiveRecord::Migration[7.2]
  def change
    add_reference :ai_chat_messages, :ai_chat_session, null: true, foreign_key: true
    add_index :ai_chat_messages, [:ai_chat_session_id, :created_at]
  end
end
