# frozen_string_literal: true

module Dashboard
  class SessionsController < ActionController::Base
    layout 'dashboard_auth'
    protect_from_forgery with: :exception

    def new
      redirect_to dashboard_root_path if session[:merchant_id].present?
    end

    def create
      merchant = nil

      # Email + password is primary; API key is optional (only if account setup complete).
      if params[:email].present? && params[:password].present?
        merchant = Merchant.where('LOWER(email) = ?', params[:email].to_s.strip.downcase).first
        merchant = nil unless merchant&.authenticate(params[:password])
        if merchant.nil?
          redirect_to dashboard_sign_in_path, alert: 'Invalid email or password'
          return
        end
      elsif params[:api_key].present?
        merchant = Merchant.find_by_api_key(params[:api_key])
        if merchant.nil?
          redirect_to dashboard_sign_in_path, alert: 'Invalid API key'
          return
        end
        unless merchant.email.present? && merchant.password_digest.present?
          redirect_to dashboard_sign_in_path,
                      alert: 'Please sign up with email and password first. You can generate and use an API key after account setup.'
          return
        end
      else
        redirect_to dashboard_sign_in_path, alert: 'Enter your email and password to sign in'
        return
      end

      session[:merchant_id] = merchant.id
      redirect_to dashboard_root_path, notice: 'Signed in successfully'
    end

    def destroy
      reset_session
      redirect_to dashboard_sign_in_path, notice: 'Signed out successfully'
    end
  end
end
