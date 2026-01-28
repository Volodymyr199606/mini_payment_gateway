module Api
  module V1
    class BaseController < ActionController::API
      include ApiAuthenticatable

      rescue_from StandardError, with: :handle_standard_error
      rescue_from ActiveRecord::RecordInvalid, with: :handle_record_invalid
      rescue_from ActionController::ParameterMissing, with: :handle_parameter_missing

      private

      def handle_standard_error(exception)
        request_id = request.env["request_id"] || Thread.current[:request_id]
        
        log_error(
          event: "exception",
          error: exception.class.name,
          message: exception.message,
          backtrace: exception.backtrace&.first(5),
          merchant_id: current_merchant&.id,
          request_id: request_id
        )
        
        render_error(
          code: "internal_error",
          message: "An unexpected error occurred.",
          status: :internal_server_error
        )
      end

      def handle_record_invalid(exception)
        render_error(
          code: "validation_error",
          message: "Validation failed",
          details: exception.record.errors.full_messages
        )
      end

      def handle_parameter_missing(exception)
        render_error(
          code: "parameter_missing",
          message: "Required parameter missing: #{exception.param}",
          status: :bad_request
        )
      end
    end
  end
end
