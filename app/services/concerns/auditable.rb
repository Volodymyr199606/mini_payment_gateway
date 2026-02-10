# frozen_string_literal: true

module Auditable
  extend ActiveSupport::Concern

  private

  def create_audit_log(action:, auditable: nil, metadata: {})
    merchant = extract_merchant

    AuditLogService.call(
      merchant: merchant,
      actor_type: 'merchant',
      actor_id: merchant&.id,
      action: action,
      auditable: auditable,
      metadata: metadata
    )
  end

  def extract_merchant
    # Try to extract merchant from common service attributes
    if respond_to?(:@payment_intent) && @payment_intent
      @payment_intent.merchant
    elsif respond_to?(:@merchant) && @merchant
      @merchant
    elsif respond_to?(:@transaction) && @transaction
      @transaction.merchant
    end
  end
end
