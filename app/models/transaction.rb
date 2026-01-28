class Transaction < ApplicationRecord
  belongs_to :payment_intent
  has_one :merchant, through: :payment_intent
  has_one :ledger_entry, dependent: :destroy

  validates :kind, inclusion: { in: %w[authorize capture void refund] }
  validates :status, inclusion: { in: %w[succeeded failed] }
  validates :amount_cents, presence: true, numericality: { greater_than: 0 }
  validates :processor_ref, uniqueness: true, allow_nil: true

  scope :succeeded, -> { where(status: "succeeded") }
  scope :failed, -> { where(status: "failed") }
  scope :authorize, -> { where(kind: "authorize") }
  scope :capture, -> { where(kind: "capture") }
  scope :void, -> { where(kind: "void") }
  scope :refund, -> { where(kind: "refund") }

  before_validation :generate_processor_ref, on: :create

  private

  def generate_processor_ref
    self.processor_ref ||= "txn_#{SecureRandom.hex(16)}"
  end
end
