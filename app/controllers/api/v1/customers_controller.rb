module Api
  module V1
    class CustomersController < BaseController
      include Paginatable

      # POST /api/v1/customers
      def create
        customer = current_merchant.customers.build(customer_params)

        if customer.save
          render json: {
            data: serialize_customer(customer)
          }, status: :created
        else
          render_error(
            code: "validation_error",
            message: "Failed to create customer",
            details: customer.errors.full_messages
          )
        end
      end

      # GET /api/v1/customers
      def index
        customers = current_merchant.customers.order(created_at: :desc)
        result = paginate(customers)

        render json: {
          data: result[:data].map { |c| serialize_customer(c) },
          meta: result[:meta]
        }
      end

      # GET /api/v1/customers/:id
      def show
        customer = current_merchant.customers.find(params[:id])

        render json: {
          data: serialize_customer(customer)
        }
      rescue ActiveRecord::RecordNotFound
        render_error(
          code: "not_found",
          message: "Customer not found",
          status: :not_found
        )
      end

      private

      def customer_params
        params.require(:customer).permit(:email, :name)
      end

      def serialize_customer(customer)
        {
          id: customer.id,
          email: customer.email,
          name: customer.name,
          created_at: customer.created_at,
          updated_at: customer.updated_at
        }
      end
    end
  end
end
