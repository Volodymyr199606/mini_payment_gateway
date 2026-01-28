module Api
  module V1
    class PaymentMethodsController < BaseController
      # POST /api/v1/customers/:customer_id/payment_methods
      def create
        customer = current_merchant.customers.find(params[:customer_id])
        payment_method = customer.payment_methods.build(payment_method_params)

        if payment_method.save
          render json: {
            data: serialize_payment_method(payment_method)
          }, status: :created
        else
          render_error(
            code: "validation_error",
            message: "Failed to create payment method",
            details: payment_method.errors.full_messages
          )
        end
      rescue ActiveRecord::RecordNotFound
        render_error(
          code: "not_found",
          message: "Customer not found",
          status: :not_found
        )
      end

      private

      def payment_method_params
        params.require(:payment_method).permit(
          :method_type,
          :last4,
          :brand,
          :exp_month,
          :exp_year
        )
      end

      def serialize_payment_method(payment_method)
        {
          id: payment_method.id,
          customer_id: payment_method.customer_id,
          method_type: payment_method.method_type,
          last4: payment_method.last4,
          brand: payment_method.brand,
          exp_month: payment_method.exp_month,
          exp_year: payment_method.exp_year,
          token: payment_method.token,
          created_at: payment_method.created_at,
          updated_at: payment_method.updated_at
        }
      end
    end
  end
end
