# frozen_string_literal: true

# Durable audit record for each AI request. No prompts, secrets, or raw payloads.
# Used for debugging, observability, and trustworthy system behavior.
class AiRequestAudit < ApplicationRecord
  self.table_name = 'ai_request_audits'

  belongs_to :merchant, optional: true

  validates :request_id, presence: true
  validates :endpoint, presence: true
  validates :agent_key, presence: true
  validates :success, inclusion: { in: [true, false] }

  scope :recent, -> { order(created_at: :desc) }
  scope :successful, -> { where(success: true) }
  scope :failed, -> { where(success: false) }
  scope :for_merchant, ->(merchant) { where(merchant_id: merchant&.id) }
end
