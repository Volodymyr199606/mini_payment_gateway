class Dashboard::PaymentIntentsController < Dashboard::BaseController
  def show
    @payment_intent = current_merchant.payment_intents
      .includes(:customer, :payment_method, :transactions)
      .find(params[:id])
    
    @transactions = @payment_intent.transactions.order(created_at: :desc)
  end
end
