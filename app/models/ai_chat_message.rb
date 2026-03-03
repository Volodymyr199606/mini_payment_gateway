# frozen_string_literal: true

class AiChatMessage < ApplicationRecord
  belongs_to :merchant

  validates :role, presence: true, inclusion: { in: %w[user assistant] }
  validates :content, presence: true

  scope :recent_first, -> { order(created_at: :desc) }
  scope :chronological, -> { order(created_at: :asc) }
end
