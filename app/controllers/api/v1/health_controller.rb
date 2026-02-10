# frozen_string_literal: true

module Api
  module V1
    class HealthController < ActionController::API
      # Health endpoint does not require authentication
      def show
        render json: { status: 'ok' }
      end
    end
  end
end
