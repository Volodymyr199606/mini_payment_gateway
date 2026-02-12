# frozen_string_literal: true

module Api
  module V1
    class PaymentIntentsController < BaseController
      include Paginatable

      # POST /api/v1/payment_intents
      def create
        payment_intent_params_hash = payment_intent_params.to_h
        idempotency_key = payment_intent_params_hash[:idempotency_key]

        # Check idempotency if key provided
        if idempotency_key.present?
          idempotency = IdempotencyService.call(
            merchant: current_merchant,
            idempotency_key: idempotency_key,
            endpoint: 'create_payment_intent',
            request_params: payment_intent_params_hash
          )

          if idempotency.result[:cached]
            render json: idempotency.result[:response_body], status: idempotency.result[:status_code]
            return
          end
        end

        payment_intent = current_merchant.payment_intents.build(payment_intent_params_hash)

        # Validate customer belongs to merchant
        if payment_intent.customer && payment_intent.customer.merchant != current_merchant
          render_error(
            code: 'validation_error',
            message: 'Customer does not belong to this merchant'
          )
          return
        end

        # Validate payment method belongs to customer if provided
        if payment_intent.payment_method && payment_intent.payment_method.customer != payment_intent.customer
          render_error(
            code: 'validation_error',
            message: 'Payment method does not belong to this customer'
          )
          return
        end

        if payment_intent.save
          response_data = {
            data: serialize_payment_intent(payment_intent)
          }

          # Store idempotency record if key provided
          if idempotency_key.present? && idempotency
            idempotency.store_response(
              response_body: response_data,
              status_code: 201
            )
          end

          render json: response_data, status: :created
        else
          render_error(
            code: 'validation_error',
            message: 'Failed to create payment intent',
            details: payment_intent.errors.full_messages
          )
        end
      end

      # GET /api/v1/payment_intents
      def index
        payment_intents = current_merchant.payment_intents
                                          .includes(:customer, :payment_method)
                                          .order(created_at: :desc)

        result = paginate(payment_intents)

        render json: {
          data: result[:data].map { |pi| serialize_payment_intent(pi) },
          meta: result[:meta]
        }
      end

      # GET /api/v1/payment_intents/:id
      def show
        payment_intent = current_merchant.payment_intents
                                         .includes(:customer, :payment_method, :transactions)
                                         .find(params[:id])

        render json: {
          data: serialize_payment_intent(payment_intent)
        }
      rescue ActiveRecord::RecordNotFound
        render_error(
          code: 'not_found',
          message: 'Payment intent not found',
          status: :not_found
        )
      end

      # POST /api/v1/payment_intents/:id/authorize
      def authorize
        payment_intent = current_merchant.payment_intents.find(params[:id])
        idempotency_key = params[:idempotency_key]

        idempotency = nil
        if idempotency_key.present?
          idempotency = IdempotencyService.call(
            merchant: current_merchant,
            idempotency_key: idempotency_key,
            endpoint: 'authorize',
            request_params: { payment_intent_id: payment_intent.id }
          )
          if idempotency.result[:cached]
            render json: idempotency.result[:response_body], status: idempotency.result[:status_code]
            return
          end
        end

        # Call service
        service = AuthorizeService.call(
          payment_intent: payment_intent,
          idempotency_key: idempotency_key
        )

        if service.success?
          response_data = {
            data: {
              transaction: serialize_transaction(service.result[:transaction]),
              payment_intent: serialize_payment_intent(service.result[:payment_intent])
            }
          }

          idempotency&.store_response(
            response_body: response_data,
            status_code: 200
          )

          render json: response_data
        else
          render_error(
            code: 'authorization_failed',
            message: service.errors.join(', ')
          )
        end
      rescue ActiveRecord::RecordNotFound
        render_error(
          code: 'not_found',
          message: 'Payment intent not found',
          status: :not_found
        )
      end

      # POST /api/v1/payment_intents/:id/capture
      def capture
        payment_intent = current_merchant.payment_intents.find(params[:id])
        idempotency_key = params[:idempotency_key]

        idempotency = nil
        if idempotency_key.present?
          idempotency = IdempotencyService.call(
            merchant: current_merchant,
            idempotency_key: idempotency_key,
            endpoint: 'capture',
            request_params: { payment_intent_id: payment_intent.id }
          )
          if idempotency.result[:cached]
            render json: idempotency.result[:response_body], status: idempotency.result[:status_code]
            return
          end
        end

        # Call service
        service = CaptureService.call(
          payment_intent: payment_intent,
          idempotency_key: idempotency_key
        )

        if service.success?
          response_data = {
            data: {
              transaction: serialize_transaction(service.result[:transaction]),
              payment_intent: serialize_payment_intent(service.result[:payment_intent])
            }
          }

          idempotency&.store_response(
            response_body: response_data,
            status_code: 200
          )

          render json: response_data
        else
          render_error(
            code: 'capture_failed',
            message: service.errors.join(', ')
          )
        end
      rescue ActiveRecord::RecordNotFound
        render_error(
          code: 'not_found',
          message: 'Payment intent not found',
          status: :not_found
        )
      end

      # POST /api/v1/payment_intents/:id/void
      def void
        payment_intent = current_merchant.payment_intents.find(params[:id])
        idempotency_key = params[:idempotency_key]

        idempotency = nil
        if idempotency_key.present?
          idempotency = IdempotencyService.call(
            merchant: current_merchant,
            idempotency_key: idempotency_key,
            endpoint: 'void',
            request_params: { payment_intent_id: payment_intent.id }
          )
          if idempotency.result[:cached]
            render json: idempotency.result[:response_body], status: idempotency.result[:status_code]
            return
          end
        end

        # Call service
        service = VoidService.call(
          payment_intent: payment_intent,
          idempotency_key: idempotency_key
        )

        if service.success?
          response_data = {
            data: {
              transaction: serialize_transaction(service.result[:transaction]),
              payment_intent: serialize_payment_intent(service.result[:payment_intent])
            }
          }

          idempotency&.store_response(
            response_body: response_data,
            status_code: 200
          )

          render json: response_data
        else
          render_error(
            code: 'void_failed',
            message: service.errors.join(', ')
          )
        end
      rescue ActiveRecord::RecordNotFound
        render_error(
          code: 'not_found',
          message: 'Payment intent not found',
          status: :not_found
        )
      end

      private

      def payment_intent_params
        params.require(:payment_intent).permit(
          :customer_id,
          :payment_method_id,
          :amount_cents,
          :currency,
          :idempotency_key,
          metadata: {}
        )
      end

      def serialize_payment_intent(payment_intent)
        {
          id: payment_intent.id,
          merchant_id: payment_intent.merchant_id,
          customer_id: payment_intent.customer_id,
          payment_method_id: payment_intent.payment_method_id,
          amount_cents: payment_intent.amount_cents,
          amount: payment_intent.amount,
          currency: payment_intent.currency,
          status: payment_intent.status,
          idempotency_key: payment_intent.idempotency_key,
          metadata: payment_intent.metadata,
          refundable_cents: payment_intent.refundable_cents,
          total_refunded_cents: payment_intent.total_refunded_cents,
          created_at: payment_intent.created_at,
          updated_at: payment_intent.updated_at
        }
      end

      def serialize_transaction(transaction)
        {
          id: transaction.id,
          payment_intent_id: transaction.payment_intent_id,
          kind: transaction.kind,
          status: transaction.status,
          amount_cents: transaction.amount_cents,
          processor_ref: transaction.processor_ref,
          failure_code: transaction.failure_code,
          failure_message: transaction.failure_message,
          created_at: transaction.created_at,
          updated_at: transaction.updated_at
        }
      end
    end
  end
end
