# frozen_string_literal: true

module Api
  module V1
    class MerchantsController < BaseController
      skip_before_action :authenticate_merchant!, only: [:create]

      # POST /api/v1/merchants - DISABLED
      # Merchants must be created via dashboard sign-up (email + password).
      # Route preserved for backward compatibility; returns 403.
      def create
        render_error(
          code: 'merchant_creation_disabled',
          message: 'Merchant creation is disabled. Please sign up at /dashboard/sign_up to create an account.',
          status: :forbidden
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
