# frozen_string_literal: true

module Dev
  # Internal AI playground for developers. Only available in development/test.
  # Inspect parsing, routing, retrieval, tools, orchestration, memory, and response.
  class AiPlaygroundController < ActionController::Base
    layout 'dev'
    skip_before_action :verify_authenticity_token, if: -> { request.format.json? }
    before_action :ensure_dev_only

    def show
      @merchants = Merchant.order(:id).limit(50)
      @presets = PRESETS
    end

    def run
      message = params[:message].to_s.strip
      merchant_id = params[:merchant_id].presence || Merchant.first&.id

      if message.blank?
        return render json: { error: 'Message is required' }, status: :bad_request
      end

      if merchant_id.blank?
        return render json: { error: 'No merchant found. Create a merchant first.' }, status: :bad_request
      end

      result = Ai::Dev::PlaygroundRunner.call(message: message, merchant_id: merchant_id)

      if result[:error]
        render json: result, status: :unprocessable_entity
      else
        render json: result
      end
    end

    private

    def ensure_dev_only
      return if Rails.env.development? || Rails.env.test?

      render plain: 'Not available', status: :not_found
    end

    PRESETS = [
      'Why did payment intent pi_123 fail?',
      'What is my net volume for the last 7 days?',
      'How do refunds work?',
      'What happened to webhook evt_abc?',
      'Show me failed captures this week'
    ].freeze
  end
end
