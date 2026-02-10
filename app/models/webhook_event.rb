# frozen_string_literal: true

class WebhookEvent < ApplicationRecord
  belongs_to :merchant, optional: true

  validates :event_type, presence: true
  validates :payload, presence: true
  validates :delivery_status, inclusion: { in: %w[pending succeeded failed] }
  validates :attempts, numericality: { greater_than_or_equal_to: 0 }

  scope :pending, -> { where(delivery_status: 'pending') }
  scope :succeeded, -> { where(delivery_status: 'succeeded') }
  scope :failed, -> { where(delivery_status: 'failed') }
end
