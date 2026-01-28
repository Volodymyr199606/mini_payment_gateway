class IdempotencyRecord < ApplicationRecord
  belongs_to :merchant

  validates :idempotency_key, presence: true
  validates :endpoint, presence: true
  validates :request_hash, presence: true
  validates :response_body, presence: true
  validates :status_code, presence: true

  validates :idempotency_key, uniqueness: { 
    scope: [:merchant_id, :endpoint],
    message: "already used for this endpoint"
  }
end
