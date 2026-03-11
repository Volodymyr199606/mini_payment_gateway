# frozen_string_literal: true

module Dashboard
  # Lightweight dev/debug view of AI request audit records. Only enabled in development or when AI_DEBUG=true.
  class AiAuditController < Dashboard::BaseController
    before_action :allow_ai_audit_inspection

    def index
      @audits = AiRequestAudit.for_merchant(current_merchant).recent.limit(100)
    end

    private

    def allow_ai_audit_inspection
      return if Rails.env.development?
      return if ENV['AI_DEBUG'].to_s.strip.downcase.in?(%w[true 1])

      redirect_to dashboard_root_path, alert: 'Not available'
    end
  end
end
