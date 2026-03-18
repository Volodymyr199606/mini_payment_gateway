# frozen_string_literal: true

module Dev
  # Internal AI health / SLO monitoring. Dev/test only.
  # Shows health status, metric statuses, and recent anomalies from ai_request_audits.
  class AiHealthController < ActionController::Base
    layout 'dev'
    before_action :ensure_dev_only

    def show
      @report = Ai::Monitoring::HealthReporter.call(merchant_id: params[:merchant_id].presence)
      @corpus_state = Ai::Rag::Corpus::StateService.call
      @merchant_id = params[:merchant_id].presence
      @merchants = Merchant.order(:id).limit(200).pluck(:id, :name, :email)
      @config_flags = Ai::Config::FeatureFlags.safe_summary

      respond_to do |format|
        format.html
        format.json { render json: @report.to_h.merge(config_flags: @config_flags) }
      end
    end

    private

    def ensure_dev_only
      return if Rails.env.development? || Rails.env.test?

      render plain: 'Not available', status: :not_found
    end
  end
end
