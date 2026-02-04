class Dashboard::LedgerController < Dashboard::BaseController
  def index
    @ledger_entries = current_merchant.ledger_entries
      .includes(:payment_transaction)
      .order(created_at: :desc)
      .page(params[:page]).per(25)
    
    # Calculate totals
    @total_charges = current_merchant.ledger_entries.charges.sum(:amount_cents)
    @total_refunds = current_merchant.ledger_entries.refunds.sum(:amount_cents).abs
    @total_fees = current_merchant.ledger_entries.fees.sum(:amount_cents)
    @net_volume = @total_charges - @total_refunds - @total_fees
  end
end
