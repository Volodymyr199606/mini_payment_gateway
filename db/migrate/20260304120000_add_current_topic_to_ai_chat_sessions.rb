# frozen_string_literal: true

class AddCurrentTopicToAiChatSessions < ActiveRecord::Migration[7.2]
  def change
    add_column :ai_chat_sessions, :current_topic, :string
  end
end
