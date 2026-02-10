# frozen_string_literal: true

module Api
  module V1
    class MerchantsController < BaseController
      skip_before_action :authenticate_merchant!, only: [:create]

      # POST /api/v1/merchants
      # Bootstrap/dev endpoint - returns plaintext API key ONCE
      # Optional: email, password — set these to sign in to the dashboard without the API key
      def create
        attrs = {
          name: params[:name] || "Merchant #{SecureRandom.hex(4)}",
          status: 'active'
        }
        attrs[:email] = params[:email].to_s.strip.presence
        merchant, api_key = Merchant.create_with_api_key(attrs)
        merchant.update!(password: params[:password]) if params[:password].present?

        render json: {
          data: {
            id: merchant.id,
            name: merchant.name,
            status: merchant.status,
            api_key: api_key
          }
        }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render_error(
          code: 'validation_error',
          message: 'Failed to create merchant',
          details: e.record.errors.full_messages
        )
      end

      # GET /api/v1/merchants/me
      def me
        render json: {
          data: {
            id: current_merchant.id,
            name: current_merchant.name,
            status: current_merchant.status,
            created_at: current_merchant.created_at
          }
        }
      end
    end
  end
end
