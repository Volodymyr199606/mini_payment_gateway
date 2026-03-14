# frozen_string_literal: true

module Dev
  # Internal AI analytics dashboard. Dev/test only.
  # Aggregates ai_request_audits for operational visibility. No prompts or secrets.
  class AiAnalyticsController < ActionController::Base
    layout 'dev'
    before_action :ensure_dev_only

    def index
      scope = Ai::Analytics::DashboardQuery.call(
        time_preset: params[:period].presence || '7d',
        merchant_id: params[:merchant_id].presence
      )
      @metrics = Ai::Analytics::MetricsBuilder.call(scope)
      @period = params[:period].presence || '7d'
      @merchant_id = params[:merchant_id].presence
      @merchants = Merchant.order(:id).limit(200).pluck(:id, :name, :email)
    end

    private

    def ensure_dev_only
      return if Rails.env.development? || Rails.env.test?

      render plain: 'Not available', status: :not_found
    end
  end
end
