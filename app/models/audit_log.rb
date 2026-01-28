class AuditLog < ApplicationRecord
  belongs_to :merchant, optional: true

  validates :actor_type, presence: true
  validates :action, presence: true

  scope :for_merchant, ->(merchant) { where(merchant: merchant) }
  scope :for_auditable, ->(auditable) { 
    where(auditable_type: auditable.class.name, auditable_id: auditable.id) 
  }
end
