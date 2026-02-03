class Dashboard::RegistrationsController < ActionController::Base
  protect_from_forgery with: :exception

  def new
    redirect_to dashboard_transactions_path if session[:merchant_id].present?
  end

  def create
    api_key = Merchant.generate_api_key
    @merchant = Merchant.new(
      name: registration_params[:name].to_s.strip.presence || "Merchant",
      status: "active",
      email: registration_params[:email].to_s.strip.presence,
      password: registration_params[:password],
      password_confirmation: registration_params[:password_confirmation],
      api_key_digest: BCrypt::Password.create(api_key)
    )

    if @merchant.save
      session[:merchant_id] = @merchant.id
      session[:new_api_key] = api_key
      redirect_to dashboard_account_path, notice: "Account created. Copy your API key below; you can also sign in with email and password."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def registration_params
    params.require(:registration).permit(:name, :email, :password, :password_confirmation)
  end
end
