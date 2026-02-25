# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Dashboard auth flow', type: :request do
  # Merchant signup: creates merchant with email/password, auto-generates API key
  describe 'POST /dashboard/sign_up' do
    it 'creates merchant with email and password and auto-generates API key' do
      post dashboard_sign_up_path, params: {
        registration: {
          name: 'Test Merchant',
          email: 'merchant@example.com',
          password: 'password123',
          password_confirmation: 'password123'
        }
      }
      expect(response).to redirect_to(dashboard_account_path)
      expect(flash[:notice]).to be_present

      merchant = Merchant.find_by(email: 'merchant@example.com')
      expect(merchant).to be_present
      expect(merchant.name).to eq('Test Merchant')
      expect(merchant.email).to eq('merchant@example.com')
      expect(merchant.password_digest).to be_present
      expect(merchant.api_key_digest).to be_present
    end

    it 'rejects signup without email' do
      post dashboard_sign_up_path, params: {
        registration: {
          name: 'Test',
          email: '',
          password: 'password123',
          password_confirmation: 'password123'
        }
      }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(Merchant.find_by(name: 'Test')).to be_nil
    end
  end

  # API key works immediately for /api/v1 requests after signup
  describe 'API key after signup' do
    it 'API key works for /api/v1 requests immediately after signup' do
      post dashboard_sign_up_path, params: {
        registration: {
          name: 'API Test Merchant',
          email: 'api_test@example.com',
          password: 'password123',
          password_confirmation: 'password123'
        }
      }
      expect(response).to redirect_to(dashboard_account_path)
      follow_redirect!
      expect(response).to have_http_status(:ok)

      # Extract API key from account page (shown once after signup)
      api_key = response.body[/<code>([a-f0-9]{64})<\/code>/, 1]
      expect(api_key).to be_present

      get '/api/v1/merchants/me', headers: api_headers(api_key)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['data']['name']).to eq('API Test Merchant')
    end
  end

  # API-key-only login blocked if email/password missing
  describe 'API-key sign-in restriction' do
    it 'blocks API-key login when merchant has no email or password' do
      # Create valid merchant then clear email/password (simulates legacy/incomplete account)
      m, _key = create_merchant_with_api_key(name: 'Legacy', email: 'legacy@example.com')
      api_key = m.regenerate_api_key
      m.update_columns(email: nil, password_digest: nil)

      post dashboard_sign_in_path, params: { api_key: api_key }
      expect(response).to redirect_to(dashboard_sign_in_path)
      expect(flash[:alert]).to include('Please sign up with email and password first')
    end

    it 'allows API-key login when merchant has email and password' do
      m, key = create_merchant_with_api_key
      post dashboard_sign_in_path, params: { api_key: key }
      expect(response).to redirect_to(dashboard_root_path)
      expect(session[:merchant_id]).to eq(m.id)
    end
  end
end
