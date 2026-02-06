class Dashboard::PaymentIntentsController < Dashboard::BaseController
  def index
    @payment_intents = current_merchant.payment_intents
      .includes(:customer)
      .order(created_at: :desc)
      .page(params[:page]).per(25)
  end

  def show
    @payment_intent = current_merchant.payment_intents
      .includes(:customer, :payment_method, :transactions)
      .find(params[:id])
    
    @transactions = @payment_intent.transactions.order(created_at: :desc)
  end
end
