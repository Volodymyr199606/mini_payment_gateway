class Dashboard::AccountController < Dashboard::BaseController
  def show
    # new_api_key is set once after regeneration and cleared after display
    @new_api_key = session.delete(:new_api_key)
  end

  def regenerate_api_key
    new_key = current_merchant.regenerate_api_key
    session[:new_api_key] = new_key
    redirect_to dashboard_account_path, notice: "API key regenerated. Copy it below; it won't be shown again."
  end

  def update_credentials
    if current_merchant.update(credentials_params)
      redirect_to dashboard_account_path, notice: "Email and password updated. You can sign in with them next time."
    else
      flash.now[:alert] = current_merchant.errors.full_messages.to_sentence
      @new_api_key = session[:new_api_key] # preserve so regenerated key still shows if they had just regenerated
      render :show, status: :unprocessable_entity
    end
  end

  private

  def credentials_params
    params.require(:merchant).permit(:email, :password).tap do |p|
      p.delete(:password) if p[:password].blank?
    end
  end
end
