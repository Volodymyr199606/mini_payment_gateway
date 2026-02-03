class Merchant < ApplicationRecord
  has_many :customers, dependent: :destroy
  has_many :payment_intents, dependent: :destroy
  has_many :ledger_entries, dependent: :destroy
  has_many :webhook_events, dependent: :destroy
  has_many :audit_logs, dependent: :destroy
  has_many :idempotency_records, dependent: :destroy

  validates :name, presence: true
  validates :status, inclusion: { in: %w[active inactive] }
  validates :api_key_digest, presence: true, uniqueness: true

  scope :active, -> { where(status: "active") }

  def self.generate_api_key
    SecureRandom.hex(32)
  end

  def self.create_with_api_key(attributes = {})
    api_key = generate_api_key
    api_key_digest = BCrypt::Password.create(api_key)
    
    merchant = create!(attributes.merge(api_key_digest: api_key_digest))
    [merchant, api_key]
  end

  def self.find_by_api_key(api_key)
    return nil if api_key.blank?

    # Find merchant by comparing hashed API key
    all.find do |merchant|
      BCrypt::Password.new(merchant.api_key_digest) == api_key
    rescue BCrypt::Errors::InvalidHash
      false
    end
  end

  def api_key_matches?(api_key)
    return false if api_key.blank?
    BCrypt::Password.new(api_key_digest) == api_key
  rescue BCrypt::Errors::InvalidHash
    false
  end

  # Regenerate API key (e.g. when user forgot it). Returns new key; old key stops working.
  def regenerate_api_key
    new_key = self.class.generate_api_key
    update!(api_key_digest: BCrypt::Password.create(new_key))
    new_key
  end
end
