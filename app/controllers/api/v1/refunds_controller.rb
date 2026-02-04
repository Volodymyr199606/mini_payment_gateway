module Api
  module V1
    class RefundsController < BaseController
      # POST /api/v1/payment_intents/:payment_intent_id/refunds
      # Only captured intents; partial via amount_cents; idempotency prevents duplicate refunds.
      def create
        payment_intent = current_merchant.payment_intents.find(params[:payment_intent_id])

        if payment_intent.status != "captured"
          render_error(
            code: "invalid_state",
            message: "Payment intent must be in 'captured' state to refund",
            status: :unprocessable_entity
          )
          return
        end

        amount_cents = refund_params[:amount_cents].present? ? refund_params[:amount_cents].to_i : payment_intent.refundable_cents

        if amount_cents > payment_intent.refundable_cents
          render_error(
            code: "validation_error",
            message: "Refund amount exceeds refundable amount",
            details: {
              refundable_cents: payment_intent.refundable_cents,
              requested_cents: amount_cents
            }
          )
          return
        end

        if amount_cents <= 0
          render_error(
            code: "validation_error",
            message: "Refund amount must be greater than zero",
            details: { refundable_cents: payment_intent.refundable_cents }
          )
          return
        end

        idempotency_key = params[:idempotency_key]

        if idempotency_key.present?
          idempotency = IdempotencyService.call(
            merchant: current_merchant,
            idempotency_key: idempotency_key,
            endpoint: "refund",
            request_params: { payment_intent_id: payment_intent.id, amount_cents: amount_cents }
          )

          if idempotency.result && idempotency.result[:cached]
            render json: idempotency.result[:response_body], status: idempotency.result[:status_code]
            return
          end
        end

        service = RefundService.call(
          payment_intent: payment_intent,
          amount_cents: amount_cents,
          idempotency_key: idempotency_key
        )

        if service.success?
          response_data = {
            data: {
              transaction: serialize_transaction(service.result[:transaction]),
              payment_intent: serialize_payment_intent(service.result[:payment_intent]),
              refund_amount_cents: service.result[:refund_amount_cents]
            }
          }

          if idempotency_key.present? && idempotency && idempotency.result && !idempotency.result[:cached]
            idempotency.store_response(
              response_body: response_data,
              status_code: 201
            )
          end

          render json: response_data, status: :created
        else
          render_error(
            code: "refund_failed",
            message: service.errors.join(", ")
          )
        end
      rescue ActiveRecord::RecordNotFound
        render_error(
          code: "not_found",
          message: "Payment intent not found",
          status: :not_found
        )
      end

      private

      def refund_params
        params.fetch(:refund, {}).permit(:amount_cents)
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
