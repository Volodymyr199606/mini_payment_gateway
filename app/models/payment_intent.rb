# frozen_string_literal: true

class PaymentIntent < ApplicationRecord
  belongs_to :merchant
  belongs_to :customer
  belongs_to :payment_method, optional: true
  has_many :transactions, dependent: :destroy

  validates :amount_cents, presence: true, numericality: { greater_than: 0 }
  validates :currency, presence: true, length: { is: 3 }
  validates :status, inclusion: {
    in: %w[created authorized captured canceled failed]
  }
  validates :idempotency_key, uniqueness: { scope: :merchant_id }, allow_nil: true

  scope :created, -> { where(status: 'created') }
  scope :authorized, -> { where(status: 'authorized') }
  scope :captured, -> { where(status: 'captured') }
  scope :canceled, -> { where(status: 'canceled') }
  scope :failed, -> { where(status: 'failed') }

  def amount
    amount_cents / 100.0
  end

  def total_refunded_cents
    transactions.where(kind: 'refund', status: 'succeeded').sum(:amount_cents)
  end

  def refundable_cents
    return 0 unless status == 'captured'

    captured_amount = transactions.where(kind: 'capture', status: 'succeeded').sum(:amount_cents)
    captured_amount - total_refunded_cents
  end
end
