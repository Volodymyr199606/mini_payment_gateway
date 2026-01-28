module Api
  module V1
    class RefundsController < BaseController
      # POST /api/v1/payment_intents/:payment_intent_id/refunds
      def create
        payment_intent = current_merchant.payment_intents.find(params[:payment_intent_id])

        if payment_intent.status != "captured"
          render_error(
            code: "invalid_state",
            message: "Payment intent must be in 'captured' state to refund"
          )
          return
        end

        amount_cents = refund_params[:amount_cents] || payment_intent.refundable_cents

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

        # Phase 3: Will implement service object
        render_error(
          code: "not_implemented",
          message: "Refund will be implemented in Phase 3"
        )
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
    end
  end
end
