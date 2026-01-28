class Dashboard::SessionsController < ActionController::Base
  protect_from_forgery with: :exception
  
  def new
    redirect_to dashboard_transactions_path if session[:merchant_id].present?
  end

  def create
    api_key = params[:api_key]
    
    if api_key.blank?
      flash.now[:alert] = "API key is required"
      render :new, status: :unprocessable_entity
      return
    end

    merchant = Merchant.find_by_api_key(api_key)
    
    if merchant
      session[:merchant_id] = merchant.id
      redirect_to dashboard_transactions_path, notice: "Signed in successfully"
    else
      flash.now[:alert] = "Invalid API key"
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    session[:merchant_id] = nil
    redirect_to dashboard_sign_in_path, notice: "Signed out successfully"
  end
end
