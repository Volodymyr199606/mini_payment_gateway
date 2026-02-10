# frozen_string_literal: true

module ApiAuthenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_merchant!
  end

  private

  def authenticate_merchant!
    api_key = request.headers['X-API-KEY']

    unless api_key.present?
      render_error(
        code: 'unauthorized',
        message: 'Missing API key. Provide X-API-KEY header.',
        status: :unauthorized
      )
      return
    end

    @current_merchant = find_merchant_by_api_key(api_key)

    return if @current_merchant

    render_error(
      code: 'unauthorized',
      message: 'Invalid API key.',
      status: :unauthorized
    )
    nil
  end

  def current_merchant
    @current_merchant
  end

  def find_merchant_by_api_key(api_key)
    Merchant.find_by_api_key(api_key)
  end

  def render_error(code:, message:, status: :unprocessable_entity, details: {})
    render json: {
      error: {
        code: code,
        message: message,
        details: details
      }
    }, status: status
  end
end
