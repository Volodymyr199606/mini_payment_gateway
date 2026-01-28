class AuditLogService < BaseService
  def initialize(merchant:, actor_type: "merchant", actor_id: nil, action:, auditable: nil, metadata: {})
    super()
    @merchant = merchant
    @actor_type = actor_type
    @actor_id = actor_id || merchant&.id
    @action = action
    @auditable = auditable
    @metadata = metadata
  end

  def call
    audit_log = AuditLog.create!(
      merchant: @merchant,
      actor_type: @actor_type,
      actor_id: @actor_id,
      action: @action,
      auditable_type: @auditable&.class&.name,
      auditable_id: @auditable&.id,
      metadata: @metadata.merge(
        request_id: Thread.current[:request_id],
        timestamp: Time.current.iso8601
      )
    )

    set_result(audit_log)
    self
  rescue StandardError => e
    add_error("Failed to create audit log: #{e.message}")
    # Don't fail the main operation if audit logging fails
    Rails.logger.error("Audit log creation failed: #{e.message}")
    self
  end
end
