# frozen_string_literal: true

class PaymentMethod < ApplicationRecord
  belongs_to :customer
  has_many :payment_intents, dependent: :nullify

  validates :method_type, presence: true, inclusion: { in: %w[card] }
  validates :token, presence: true, uniqueness: true
  validates :last4, length: { is: 4 }, allow_nil: true
  validates :exp_month, inclusion: { in: 1..12 }, allow_nil: true
  validates :exp_year, numericality: { greater_than_or_equal_to: Date.current.year }, allow_nil: true

  before_validation :generate_token, on: :create

  private

  def generate_token
    self.token ||= "pm_#{SecureRandom.hex(16)}"
  end
end
