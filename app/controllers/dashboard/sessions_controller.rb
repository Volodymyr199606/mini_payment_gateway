class Dashboard::SessionsController < ActionController::Base
  protect_from_forgery with: :exception
  
  def new
    redirect_to dashboard_transactions_path if session[:merchant_id].present?
  end

  def create
    merchant = nil

    if params[:api_key].present?
      merchant = Merchant.find_by_api_key(params[:api_key])
      if merchant.nil?
        flash.now[:alert] = "Invalid API key"
        render :new, status: :unprocessable_entity
        return
      end
    elsif params[:email].present? && params[:password].present?
      merchant = Merchant.where("LOWER(email) = ?", params[:email].to_s.strip.downcase).first
      merchant = nil unless merchant&.authenticate(params[:password])
      if merchant.nil?
        flash.now[:alert] = "Invalid email or password"
        render :new, status: :unprocessable_entity
        return
      end
    else
      flash.now[:alert] = "Enter your API key or email and password"
      render :new, status: :unprocessable_entity
      return
    end

    session[:merchant_id] = merchant.id
    redirect_to dashboard_transactions_path, notice: "Signed in successfully"
  end

  def destroy
    reset_session
    redirect_to dashboard_sign_in_path, notice: "Signed out successfully"
  end
end
