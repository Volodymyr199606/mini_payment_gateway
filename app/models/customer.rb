class Customer < ApplicationRecord
  belongs_to :merchant
  has_many :payment_methods, dependent: :destroy
  has_many :payment_intents, dependent: :destroy

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :email, uniqueness: { scope: :merchant_id, message: "already exists for this merchant" }
end
