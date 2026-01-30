class Dashboard::BaseController < ActionController::Base
  protect_from_forgery with: :exception
  layout "dashboard"
  before_action :authenticate_merchant!
  helper_method :current_merchant

  private

  def authenticate_merchant!
    @current_merchant = Merchant.find_by(id: session[:merchant_id])
    
    unless @current_merchant
      redirect_to dashboard_sign_in_path, alert: "Please sign in to continue"
    end
  end

  def current_merchant
    @current_merchant
  end

  def sign_in(merchant)
    session[:merchant_id] = merchant.id
  end

  def sign_out
    session[:merchant_id] = nil
  end
end
