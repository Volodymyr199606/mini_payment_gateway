class LedgerEntry < ApplicationRecord
  belongs_to :merchant
  belongs_to :transaction, optional: true

  validates :entry_type, inclusion: { in: %w[charge refund fee] }
  validates :amount_cents, presence: true
  validates :currency, presence: true, length: { is: 3 }

  # Convention: positive amounts for charges, negative for refunds
  # Fees can be positive (merchant pays) or negative (merchant receives)
  scope :charges, -> { where(entry_type: "charge") }
  scope :refunds, -> { where(entry_type: "refund") }
  scope :fees, -> { where(entry_type: "fee") }
end
