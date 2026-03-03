# frozen_string_literal: true

class AiChatSession < ApplicationRecord
  belongs_to :merchant
  has_many :ai_chat_messages, dependent: :destroy
end
