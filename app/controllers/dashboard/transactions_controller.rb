# frozen_string_literal: true

module Dashboard
  class TransactionsController < Dashboard::BaseController
    def index
      # Query transactions directly from database
      transactions = Transaction.joins(:payment_intent)
                                .where(payment_intents: { merchant_id: current_merchant.id })
                                .includes(:payment_intent)
                                .order(created_at: :desc)

      # Apply filters
      transactions = transactions.where(status: params[:status]) if params[:status].present?
      transactions = transactions.where(kind: params[:kind]) if params[:kind].present?

      # Date range filter
      if params[:date_from].present?
        transactions = transactions.where('transactions.created_at >= ?', Date.parse(params[:date_from]))
      end
      if params[:date_to].present?
        transactions = transactions.where('transactions.created_at <= ?', Date.parse(params[:date_to]).end_of_day)
      end

      @transactions = transactions.page(params[:page]).per(25)
    end
  end
end
