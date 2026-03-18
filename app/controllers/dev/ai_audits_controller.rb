# frozen_string_literal: true

module Dev
  # Internal AI audit drill-down. Dev/test only.
  # Browse and inspect individual ai_request_audits. No prompts or secrets.
  class AiAuditsController < ActionController::Base
    layout 'dev'
    before_action :ensure_dev_only
    # Dev-only endpoint; avoid CSRF failures in request specs.
    skip_before_action :verify_authenticity_token, only: :replay

    def index
      safe_filters = filter_params
      @audits = Ai::AuditTrail::QueryBuilder.call(
        params: safe_filters,
        limit: 100
      )
    ensure
      @filters = safe_filters || filter_params
      @merchants = load_merchants_for_filter
    end

    def show
      @audit = AiRequestAudit.find_by(id: params[:id])
      unless @audit
        redirect_to dev_ai_audits_path, alert: 'Audit not found'
        return
      end
      @presented = Ai::AuditTrail::DetailPresenter.call(@audit)
      @replay_result = flash[:replay_result].presence
    rescue StandardError
      redirect_to dev_ai_audits_path, alert: 'Audit not found'
    end

    def replay
      @audit = AiRequestAudit.find_by(id: params[:id])
      unless @audit
        redirect_to dev_ai_audits_path, alert: 'Audit not found'
        return
      end

      result = Ai::Replay::RequestReplayer.call(
        audit_id: params[:id],
        request_id: "replay-#{params[:id]}-#{SecureRandom.hex(4)}"
      )
      flash[:replay_result] = result.to_h
      redirect_to dev_ai_audit_path(@audit), notice: result.replay_possible ? 'Replay completed.' : 'Replay not possible for this request.'
    rescue StandardError => e
      Rails.logger.warn("[Dev::AiAuditsController] Replay failed: #{e.message}")
      redirect_to dev_ai_audit_path(params[:id]), alert: "Replay failed: #{e.message}"
    end

    private

    def ensure_dev_only
      return if Rails.env.development? || Rails.env.test?

      render plain: 'Not available', status: :not_found
    end

    def filter_params
      {
        from: params[:from].presence,
        to: params[:to].presence,
        merchant_id: params[:merchant_id].presence,
        agent_key: params[:agent_key].presence,
        composition_mode: params[:composition_mode].presence,
        degraded_only: params[:degraded_only].to_s.in?(%w[1 true]),
        fallback_only: params[:fallback_only].to_s.in?(%w[1 true]),
        policy_blocked_only: params[:policy_blocked_only].to_s.in?(%w[1 true]),
        tool_used: params[:tool_used].presence,
        request_id: params[:request_id].presence,
        failed_only: params[:failed_only].to_s.in?(%w[1 true]),
        high_latency_only: params[:high_latency_only].to_s.in?(%w[1 true]),
        min_latency_ms: params[:min_latency_ms].presence
      }.compact
    end

    def load_merchants_for_filter
      Merchant.order(:id).limit(200).pluck(:id, :name, :email)
    rescue StandardError
      []
    end
  end
end
